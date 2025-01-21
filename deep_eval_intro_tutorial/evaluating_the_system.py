# does not exist in the default deepeval included
# doc says to use 'from deepeval.test_case_import import LLMTestCaseParams' but that no longer exists
import json

from deepeval.test_case import LLMTestCaseParams, LLMTestCase
from deepeval.metrics import GEval

from deepeval.metrics import (
    AnswerRelevancyMetric,
    ContextualRelevancyMetric
)
from deepeval import evaluate
from medical_appointment_system import MODEL, SYSTEM_PROMPT, TEMPERATURE
from deepeval.metrics import FaithfulnessMetric

answer_relevancy_metric = AnswerRelevancyMetric()
contextual_relevancy_metric = ContextualRelevancyMetric()

# Define criteria for evaluating professionalism
criteria = """Determine whether the actual output demonstrates professionalism by being
clear, respectful, and maintaining an empathetic tone consistent with medical interactions."""

# Create a GEval metric for professionalism
professionalism_metric = GEval(
    name="Professionalism",
    criteria=criteria,
    evaluation_params=[LLMTestCaseParams.ACTUAL_OUTPUT]
)

def load_test_cases(json_file="core_test_cases.json"):
    with open(json_file, "r") as file:
        test_cases = json.load(file)
        llm_test_cases = [
            LLMTestCase(
                input=item["user_query"],
                actual_output=item["llm_output"],
                retrieval_context=[]
            )
            for item in test_cases
        ]
    return llm_test_cases

faithfulness_metric = FaithfulnessMetric(
    threshold=0.7,
    model="gpt-4",
    include_reason=True
)

if __name__ == "__main__":
    evaluate(
        load_test_cases(),
        metrics=[answer_relevancy_metric, faithfulness_metric, professionalism_metric],
        skip_on_missing_params=True,
        hyperparameters={"model": MODEL, "prompt template": SYSTEM_PROMPT, "temperature": TEMPERATURE}
    )

