from pathlib import Path
import hashlib, json, pickle
from llama_index.core import SimpleDirectoryReader
import aiofiles
from usp.tree import sitemap_from_str
import os
import asyncio
import requests
from crawl4ai import AsyncWebCrawler, CrawlerRunConfig

import time
from contextlib import contextmanager

# download the pdfs from the google drive file_ids
pdf_urls = [
    "0B7HZIUBvCH1EVGxpNEdXVklLQk0",
    "0B7HZIUBvCH1EaklDOFhPUHo0eTQ",
    "0B7HZIUBvCH1EVGxpNEdXVklLQk0",
    "0B7HZIUBvCH1EZ1REYVFnYjZscTQ"
]

# Function to download the PDF
# https://drive.usercontent.google.com/u/0/uc?id=0B7HZIUBvCH1EVGxpNEdXVklLQk0&export=download
def download_pdf(google_doc_id, filename):
    response = requests.get(f"https://drive.usercontent.google.com/u/0/uc?id={google_doc_id}&export=download", stream=True)
    if response.status_code == 200:
        with open(filename, "wb") as pdf_file:
            for chunk in response.iter_content(chunk_size=1024):
                pdf_file.write(chunk)
        print(f"Downloaded: {filename}")
    else:
        print(f"Failed to download: {filename} - Status Code: {response.status_code}")


def download_pdfs(google_doc_ids):
    # Loop through the URLs and download each PDF
    for index, id in enumerate(google_doc_ids):
        # Generate the filename
        filename = f"data/document_{index + 1}.pdf"
        # Download the PDF
        download_pdf(id, filename)

def chunk_documents(input_data_dir):
    """

    :param input_data_dir:
    :return: a tuple indicating whether there are changes and the documents (changes, documents)
    """
    doc_dir = os.path.join(input_data_dir, "documents.pkl")
    """Calculate a hash based on the contents of the directory."""
    hash_obj = hashlib.md5()
    for root, _, files in os.walk(input_data_dir):
        for file in sorted(files):  # Ensure consistent order
            # don't read the 'hash.json' file
            if file != 'hash.json' and file != 'documents.pkl':
                with open(os.path.join(root, file), 'rb') as f:
                    hash_obj.update(f.read())
    current_hash = hash_obj.hexdigest()

    # Check if hash file exists and compare hashes
    hash_path = os.path.join(input_data_dir, "hash.json")

    if os.path.exists(hash_path):
        with open(hash_path, 'r') as f:
            saved_hash = json.load(f).get('hash')
    else:
        saved_hash = None

    if saved_hash == current_hash:
        changes = False
        if os.path.exists(os.path.join(input_data_dir, "documents.pkl")):
            with open(doc_dir, "rb") as f:
                documents = pickle.load(f)
            return changes, documents
        else:
            # Load new documents from the input directory
            documents = SimpleDirectoryReader(input_data_dir, exclude=["hash.json", "documents.pkl"]).load_data()
            return changes, documents

    else:
        changes = True
        documents = SimpleDirectoryReader(input_data_dir).load_data()
        # Save the new hash
        with open(hash_path, 'w') as f:
            json.dump({'hash': current_hash}, f)
        with open(doc_dir, "wb") as f:
            pickle.dump(documents, f)
        return changes, documents




@contextmanager
def time_block(label):
    start = time.perf_counter()
    print(f"starting {label}")
    try:
        yield
    finally:
        end = time.perf_counter()
        elapsed = end - start
        print(f"{label}: {elapsed:.4f} seconds")

async def save_content_to_file(url, content, output_dir):
    # Ensure the output directory exists
    os.makedirs(output_dir, exist_ok=True)

    # Generate a safe filename based on the URL
    filename = generate_filename_from_url(url)
    file_path = os.path.join(output_dir, filename)

    # Write the content to the file asynchronously
    async with aiofiles.open(file_path, 'w', encoding='utf-8') as f:
        await f.write(content)
    print(f"Content from {url} saved to {file_path}")

def generate_filename_from_url(url):
    # Generate a safe filename based on the URL
    filename = url.replace("https://", "").replace("/", "_") + ".md"
    return filename

async def crawl_lancedb_guides(output_directory="data"):
    sitemap_url = "https://lancedb.github.io/lancedb/sitemap.xml"

    # Parse the sitemap to extract URLs
    site_map = requests.get(sitemap_url).text
    parsed_sitemap = sitemap_from_str(site_map)
    urls = [page.url for page in parsed_sitemap.all_pages()]

    # Configure the crawler for concurrent requests
    run_config = CrawlerRunConfig()

    # filter urls to only include those that start with https://lancedb.github.io/lancedb
    urls = [url for url in urls if url.startswith("https://lancedb.github.io/lancedb")]
    # exclude urls with /lancedb/javascript/ or /lancedb/python/ or /lancedb/js/
    urls = [url for url in urls if all(exclusion not in url for exclusion in ["/lancedb/javascript/",
                                                                              "/lancedb/python/", "/lancedb/js/",
                                                                              "/lancedb/examples/", "/lancedb/notebooks/","/lancedb/embeddings/"])]

    urls_not_downloaded = []
    for url in urls:
        file_path = Path(output_directory) / generate_filename_from_url(url)

        # Check if the file already exists
        if file_path.exists():
            continue
        else:
            urls_not_downloaded.append(url)


    async with AsyncWebCrawler() as crawler:
        # Crawl all URLs concurrently
        results = await crawler.arun_many(urls_not_downloaded, config=run_config)

        # Process and save the results
        tasks = []
        for result in results:
            if result.success:
                tasks.append(save_content_to_file(result.url, result.markdown, output_directory))
            else:
                print(f"Failed to crawl {result.url}: {result.error_message}")

        # Await all save tasks
        await asyncio.gather(*tasks)


# async def save_content_to_file(url, content, output_dir):
#     # Ensure the output directory exists
#     os.makedirs(output_dir, exist_ok=True)
#
#     # Generate a safe filename based on the URL
#     filename = url.replace("https://", "").replace("/", "_") + ".md"
#     file_path = os.path.join(output_dir, filename)
#
#     # Write the content to the file asynchronously
#     async with aiofiles.open(file_path, 'w', encoding='utf-8') as f:
#         await f.write(content)
#     print(f"Content from {url} saved to {file_path}")
#
#
# async def crawl_lancedb_guides(output_directory = "data"):
#     sitemap_url = "https://lancedb.github.io/lancedb/sitemap.xml"
#     output_directory = "data"
#
#     # Parse the sitemap to extract URLs
#     from usp.tree import sitemap_from_str
#
#     # Load your sitemap and parse it in
#     # download sitemap_url as string
#     site_map = requests.get(sitemap_url).text
#     parsed_sitemap = sitemap_from_str(site_map)
#
#     urls = [page.url for page in parsed_sitemap.all_pages()]
#
#     async with AsyncWebCrawler() as crawler:
#         # Crawl each extracted URL
#         for url in urls:
#             page_result = await crawler.arun(url=url)
#             if page_result.success:
#                 # Save the markdown content to a file
#                 await save_content_to_file(url, page_result.markdown, output_directory)
#             else:
#                 print(f"Failed to crawl {url}: {page_result.error_message}")
#
