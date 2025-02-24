import argparse
import asyncio
import hashlib

from langchain.chains.summarize import load_summarize_chain
from langchain.prompts import PromptTemplate
from langchain.schema import Document
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import DirectoryLoader, PyMuPDFLoader
from langchain_community.vectorstores import LanceDB
from langchain_ollama import OllamaEmbeddings
from langchain_ollama.llms import OllamaLLM

import lancedb

defaults = {
    "embedding_model": "snowflake-arctic-embed2",
    "catalog_table_name": "catalog",
    "chunks_table_name": "chunks",
    "summarization_model": "llama3.2"
}

catalog_table_name = "catalog"
chunks_table_name = "chunks"
summarization_model = "llama3.2"
embedding_model = "snowflake-arctic-embed2"

base_url="http://127.0.0.1:11434"

def parse_arguments():
    parser = argparse.ArgumentParser(description="Process documents and store summaries in LanceDB.")
    parser.add_argument("--dbpath", required=True, help="Path to the LanceDB database.")
    parser.add_argument("--filesdir", required=True, help="Path to the directory containing documents.")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing data.")
    return parser.parse_args()


def validate_args(args):
    if not args.dbpath or not args.filesdir:
        print("Please provide a database path (--dbpath) and a directory with files (--filesdir) to process.")
        exit(1)
    print("DATABASE PATH:", args.dbpath)
    print("FILES DIRECTORY:", args.filesdir)
    print("OVERWRITE FLAG:", args.overwrite)


def compute_hash(file_path):
    with open(file_path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


async def catalog_record_exists(catalog_table, file_hash):
    query = catalog_table.search(file_hash, k=1).to_list()
    return bool(query)


def get_directory_loader(files_dir):
    return DirectoryLoader(files_dir, glob="**/*.pdf", loader_cls=PyMuPDFLoader)


async def generate_content_overview(raw_docs, model):
    prompt_template = PromptTemplate(
        input_variables=["text"],
        template="""Write a high-level one sentence content overview based on the text below:
        "{text}"
        WRITE THE CONTENT OVERVIEW ONLY, DO NOT WRITE ANYTHING ELSE:
        """
    )

    chain = load_summarize_chain(model, chain_type="map_reduce", combine_prompt=prompt_template)
    res = await chain.ainvoke({"input_documents": raw_docs})
    print(res)
    return res["output_text"]


async def process_documents(raw_docs, catalog_table, model, skip_exists_check):
    docs_by_source = {}
    for doc in raw_docs:
        source = doc.metadata.get("source")
        docs_by_source.setdefault(source, []).append(doc)

    skip_sources = []
    catalog_records = []

    for source, docs in docs_by_source.items():
        file_hash = compute_hash(source)
        exists = not skip_exists_check and await catalog_record_exists(catalog_table, file_hash)
        if exists:
            print(f"Document with hash {file_hash} already exists in the catalog. Skipping...")
            skip_sources.append(source)
        else:
            content_overview = await generate_content_overview(docs, model)
            print(f"Content overview for {source}: {content_overview}")
            catalog_records.append(
                Document(page_content=content_overview, metadata={"source": source, "hash": file_hash}))

    return skip_sources, catalog_records


async def seed(args=None):
    args = parse_arguments() if args is None else args
    validate_args(args)

    db = lancedb.connect(args.dbpath)
    model = OllamaLLM(model=summarization_model, base_url=base_url)

    try:
        catalog_table = db.open_table(catalog_table_name)
    except:
        print(f"Catalog table '{catalog_table_name}' does not exist. It will be created.")
        catalog_table = None

    try:
        chunks_table = db.open_table(chunks_table_name)
    except:
        print(f"Chunks table '{chunks_table_name}' does not exist. It will be created.")
        chunks_table = None

    if args.overwrite:
        try:
            db.drop_table(catalog_table_name)
            db.drop_table(chunks_table_name)
        except:
            print("Error dropping tables. Maybe they don't exist!")

    print("Loading files...")
    directory_loader = get_directory_loader(args.filesdir)
    raw_docs = directory_loader.load()

    for doc in raw_docs:
        doc.metadata = {"loc": doc.metadata.get("loc"), "source": doc.metadata.get("source")}

    print("Processing documents...")
    skip_sources, catalog_records = await process_documents(raw_docs, catalog_table, model,
                                                            args.overwrite or not catalog_table)

    catalog_store = (LanceDB.from_documents(catalog_records, OllamaEmbeddings(model=embedding_model, base_url=base_url),
                                            uri=args.dbpath, table_name=catalog_table_name)
                     if catalog_records else LanceDB(None, OllamaEmbeddings(model=embedding_model, base_url=base_url),
                                                     uri=args.dbpath, table=catalog_table))

    print("Number of new catalog records:", len(catalog_records))
    print("Number of skipped sources:", len(skip_sources))

    filtered_raw_docs = [doc for doc in raw_docs if doc.metadata.get("source") not in skip_sources]

    print("Loading LanceDB vector store...")
    splitter = RecursiveCharacterTextSplitter(chunk_size=500, chunk_overlap=10)
    docs = splitter.split_documents(filtered_raw_docs) # change to filtered_raw_docs when doing catalog

    vector_store = (
        LanceDB.from_documents(docs, OllamaEmbeddings(model=embedding_model, base_url=base_url), uri=args.dbpath,
                               table_name=chunks_table_name)
        if docs else LanceDB(None, OllamaEmbeddings(model=embedding_model, base_url=base_url), uri=args.dbpath,
                             table=chunks_table))

    print("Number of new chunks:", len(docs))


# FOR WINDOWS ONLY
import subprocess
import time

OLLAMA_PATH = r"C:\Users\gmsharpe\AppData\Local\Programs\Ollama\ollama.exe"  # Update if needed

def start_ollama():
    """Start Ollama in the background."""
    try:
        process = subprocess.Popen(
            [OLLAMA_PATH, "serve"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            creationflags=subprocess.CREATE_NO_WINDOW  # Hide the terminal window
        )
        print("Ollama server started successfully!")
        time.sleep(2)  # Give it time to start
        return process  # Return the process object for tracking
    except Exception as e:
        print(f"Error starting Ollama: {e}")
        return None

def stop_ollama(process):
    """Stops the Ollama server process."""
    if process:
        process.terminate()  # Graceful shutdown
        print("Ollama server stopped.")


if __name__ == "__main__":
    temp_db_path = "lancedb/test_db"
    temp_files_dir = "sample-docs"

    # FOR WINDOWS ONLY
    ollama_process = start_ollama()

    class Args:
        def __init__(self, dbpath, filesdir, overwrite):
            self.dbpath = dbpath
            self.filesdir = filesdir
            self.overwrite = overwrite

    asyncio.run(seed(args=Args(dbpath=temp_db_path, filesdir=temp_files_dir, overwrite=True)))

    #stop_ollama(ollama_process)
