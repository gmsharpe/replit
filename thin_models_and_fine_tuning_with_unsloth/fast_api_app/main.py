import argparse
import logging
from datetime import datetime

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from lllama_app import LlamaApp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Parse command-line arguments
parser = argparse.ArgumentParser(description="Run FastAPI with LLaMA model.")
parser.add_argument("--model-path", type=str, required=False, help="Path to the LLaMA model file.")
args, _ = parser.parse_known_args()

MODEL_PATH = args.model_path if args.model_path is not None else "model/unsloth.Q4_K_M.gguf"

logger.info(f"Model Path: {MODEL_PATH}")

# Initialize LLaMA model
try:
    llama_app = LlamaApp(MODEL_PATH)
    logger.info(f"Model loaded successfully from {MODEL_PATH}")
except Exception as e:
    logger.error(f"Failed to load model: {e}")
    raise

app = FastAPI()

class ClassifyTicketRequest(BaseModel):
    text: str

class ClassifyTicketResponse(BaseModel):
    product_name: str
    brief_description: str
    issue_classification: str


# ✅ API Route
@app.post("/classify_ticket", response_model=ClassifyTicketResponse)
def classify_ticket(request: ClassifyTicketRequest):
    start_time = datetime.now()
    try:
        return llama_app.structured_completion(request.text,
                                               temp=1.0,
                                               max_tokens=512,
                                               response_model=ClassifyTicketResponse)

    except Exception as e:
        logger.error(f"Error in API: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        elapsed_time = (datetime.now() - start_time).total_seconds()
        logger.info(f"Processed /classify_ticket in {elapsed_time:.4f} seconds")

import uvicorn

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
