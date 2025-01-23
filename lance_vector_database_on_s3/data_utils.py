import requests, os, hashlib, json, pickle
from llama_index.core import SimpleDirectoryReader

# download the pdfs from the google drive file_ids
pdf_urls = [
    "0B7HZIUBvCH1EVGxpNEdXVklLQk0",
    "0B7HZIUBvCH1EaklDOFhPUHo0eTQ",
    "0B7HZIUBvCH1EVGxpNEdXVklLQk0",
    "0B7HZIUBvCH1EZ1REYVFnYjZscTQ"
]

# Function to download the PDF
# https://drive.usercontent.google.com/u/0/uc?id=0B7HZIUBvCH1EVGxpNEdXVklLQk0&export=download
def download_pdf(id, filename):
    response = requests.get(f"https://drive.usercontent.google.com/u/0/uc?id={id}&export=download", stream=True)
    if response.status_code == 200:
        with open(filename, "wb") as pdf_file:
            for chunk in response.iter_content(chunk_size=1024):
                pdf_file.write(chunk)
        print(f"Downloaded: {filename}")
    else:
        print(f"Failed to download: {filename} - Status Code: {response.status_code}")


def download_pdfs(ids):
    # Loop through the URLs and download each PDF
    for index, id in enumerate(ids):
        # Generate the filename
        filename = f"data/document_{index + 1}.pdf"
        # Download the PDF
        download_pdf(id, filename)

def changes_detected(input_data_dir):
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
        # Save the new hash
        with open(hash_path, 'w') as f:
            json.dump({'hash': current_hash}, f)
        saved_hash = None

    if saved_hash == current_hash:
        print("No changes in the data directory. Skipping vectorization.")
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
        with open(doc_dir, "wb") as f:
            pickle.dump(documents, f)
        return changes, documents