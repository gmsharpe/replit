import logging

import llama_cpp
import instructor
from fastapi import HTTPException

from llama_cpp.llama_speculative import LlamaPromptLookupDecoding

from thin_models_and_fine_tuning_with_unsloth.fast_api_app.prompts import SYSTEM_PROMPT, USER_PROMPT

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# https://python.useinstructor.com/integrations/llama-cpp-python/
class LlamaApp:
    def __init__(self, model_path: str):
        """
        ✅ Initializes the LLaMA model.
        """
        try:
            llama = llama_cpp.Llama(
                model_path=model_path,
                n_gpu_layers=-1,
                chat_format="chatml",
                n_ctx=2048,
                draft_model=LlamaPromptLookupDecoding(num_pred_tokens=2),
                logits_all=True,
                verbose=False,
            )

            self.create = instructor.patch(
                create=llama.create_chat_completion_openai_v1,
                mode=instructor.Mode.JSON_SCHEMA,
            )

            logger.info("Model loaded successfully!")

        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            raise

    # ✅ Function to classify customer support tickets
    def structured_completion(self,
                              ticket_text: str,
                              temp=1.0,
                              max_tokens=512,
                              response_model=None):

        try:
            response = self.create(
                messages=[
                    {"role": "system",
                     "content": SYSTEM_PROMPT},
                    {"role": "user",
                     "content": USER_PROMPT.format(ticket_text)},
                ],
                response_model=response_model,
                temperature=temp,
                max_tokens=max_tokens,
            )

            logger.info(f"Generated structured response: {response}")
            return response

        except Exception as e:
            logger.error(f"Error processing LLM response: {e}")
            raise HTTPException(status_code=500,
                                detail="Model failed to return valid structured output.")
