import json
from asyncio import gather

from medical_appointment_system import MedicalAppointmentSystem

data = [
    {
        "user_query": "Hey, I've been experiencing headaches lately.",
        "llm_output": """I can help you with that. Could you please provide more specific details about
your headaches? For example, the location, intensity, duration, frequency, and
any other symptoms you might be experiencing alongside the headaches."""
    },
    {
        "user_query": "I've been coughing a lot lately.",
        "llm_output": "Could you please provide your name, the date for the appointment, and your email address?"
    },
    {
        "user_query": "I'm feeling pretty sick, can I book an appointment tomorrow?",
        "llm_output": """I can help you with that. Could you please provide more
specific details about your symptoms? This will help us in making a more accurate diagnosis."""
    },
    {
        "user_query": """My name is John Doe. My email is johndoe@gmail.com, and I would
like to make an appointment on November 23, 2022.""",
        "llm_output": """Please confirm the following details: Name: John Doe, Email: johndoe@gmail.com,
Date: November 23, 2022, Symptoms: Frequent coughing, Diagnosis: Frequent coughing
may indicate chronic bronchitis, especially if accompanied by phlegm, wheezing, or
shortness of breath.. Type 'confirm' to finalize or 'edit' to modify."""
    },
    {
        "user_query": "My nose has been running constantly. Could it be something serious?",
        "llm_output": """It’s probably nothing to worry about. Most likely just allergies or
a cold. Don’t overthink it."""
    }
]

from deepeval.test_case import LLMTestCase


test_cases = [
    LLMTestCase(
        input=item["user_query"],
        actual_output=item["llm_output"],
        retrieval_context=[]
    )
    for item in data
]

def gather_retrieval_context():
    results = []
    system = MedicalAppointmentSystem(data_directory="./data", db_path="./chroma_db")

    for test_case in test_cases:
        response = system.chat(test_case.input)

        query_response = system.index.as_query_engine().query(test_case.input)
        print("Query Response:", query_response.response)

        # Create a JSON record for the test case
        result = {
            "user_query": test_case.input,
            "llm_output": response.response,
            "retrieval_context": query_response.response,
        }
        results.append(result)

    # Write results to a JSON file
    with open("core_test_cases.json", "w") as json_file:
        json.dump(results, json_file, indent=4)

    print("Evaluation results saved to 'evaluation_results.json'")


if __name__ == "__main__":
    gather_retrieval_context()