import asyncio
import tempfile
import os
from pathlib import Path

from python.src.seed import seed  # Assuming your script is saved as `main_script.py`

async def run_test():
    # Create a temporary directory for testing
    temp_db_path = "D:\\git-gms\\replit\\lance_db_mcp_with_sse\\python\\src\\lancedb\\test_db"
    temp_files_dir = "D:\\git-gms\\replit\\lance_db_mcp_with_sse\\sample-docs"

    # Create a dummy PDF file for testing
    # test_pdf_path = Path(temp_files_dir) / "dummy_file.pdf"
    # with open(test_pdf_path, "wb") as f:
    #     f.write(b"%PDF-1.4\n%Dummy PDF content")

    class Args:
        def __init__(self, dbpath, filesdir, overwrite):
            self.dbpath = dbpath
            self.filesdir = filesdir
            self.overwrite = overwrite

    # Run the seed function
    await seed(args=Args(dbpath=temp_db_path, filesdir=temp_files_dir, overwrite=True))

    # # Clean up (optional)
    # os.remove(test_pdf_path)
    # os.rmdir(temp_files_dir)
    # os.rmdir(temp_db_path)

# Run the test
asyncio.run(run_test())
