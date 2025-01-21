import hashlib
import json
import os

import chromadb
from llama_index.core import VectorStoreIndex, SimpleDirectoryReader, StorageContext
from llama_index.vector_stores.chroma import ChromaVectorStore
from llama_index.core.tools import FunctionTool
from llama_index.core.tools import QueryEngineTool
from llama_index.core.agent import FunctionCallingAgent
from llama_index.core.llms import ChatMessage
from llama_index.llms.openai import OpenAI
from pydantic import BaseModel
from typing import Optional


MODEL = "gpt-4o" # "gpt-3.5"
TEMPERATURE = 1.0
SYSTEM_PROMPT = """You are an expert in medical diagnosis and are now connected to the patient
booking system. The first step is to create the appointment and record the symptoms. Ask for specific
symptoms! Then after the symptoms have been created, make a diagnosis. Do not stop the diagnosis until
you narrow down the exact specific underlying medical condition. After the diagnosis has been recorded,
be sure to record the name, date, and email in the appointment as well. Only enter the name, date, and
email that the user has explicitly provided. Update the symptoms and diagnosis in the appointment.
Once all information has been recorded, confirm the appointment."""


class MedicalAppointment(BaseModel):
    """
        "Since our chatbot will be recording patient information, we’ll need a structured way to store it. We'll define a
         pydantic model with the relevant fields (symptoms, diagnoses, and personal information) to ensure that our agent
         can accurately store data in the correct format."

        Evaluation Criteria:
            Directly addressing the user: The chatbot should directly address users' requests
            Providing accurate diagnoses: Diagnoses must be reliable and based on the provided symptoms
            Providing professional responses: Responses should be clear and respectful

        Evaluation Metrics:
            https://docs.ragas.io/en/stable/
            https://docs.confident-ai.com/



    """
    name: Optional[str] = None
    email: Optional[str] = None
    date: Optional[str] = None
    symptoms: Optional[str] = None
    diagnosis: Optional[str] = None

class MedicalAppointmentSystem:
    """
            "... a MedicalAppointmentSystem class to represent our agent. This class will store all MedicalAppointment
         instances in an appointments dictionary, with each key representing a unique user."

        "Let's start by building our RAG engine, which will handle all patient diagnoses. The first step is to load
         the relevant medical information chunks from our knowledge base into the system. We'll use the
         SimpleDirectoryReader from llama-index to accomplish this."

        "Then, we'll use LlamaIndex's VectorStoreIndex to embed our chunks and store them in a chromadb database.
         This step is crucial, as our encyclopedia contains over 4,000 pages of dense medical information."


    """
    def __init__(self, data_directory, db_path):
        self.appointments = {}
        self.get_or_create_vector_store_index(db_path, data_directory)
        self.setup_tools()
        self.setup_agent()


    def changes_detected(self, data_directory):
        """Calculate a hash based on the contents of the directory."""
        hash_obj = hashlib.md5()
        for root, _, files in os.walk(data_directory):
            for file in sorted(files):  # Ensure consistent order
                # don't read the 'hash.json' file
                if file != 'hash.json':
                    with open(os.path.join(root, file), 'rb') as f:
                        hash_obj.update(f.read())
        current_hash = hash_obj.hexdigest()

        # Check if hash file exists and compare hashes
        hash_path = os.path.join(data_directory, "hash.json")
        if os.path.exists(hash_path):
            with open(hash_path, 'r') as f:
                saved_hash = json.load(f).get('hash')
            if saved_hash == current_hash:
                print("No changes in the data directory. Skipping vectorization.")
                return False

        # Save the new hash
        with open(hash_path, 'w') as f:
            json.dump({'hash': current_hash}, f)

        return True

    def get_or_create_vector_store_index(self, db_path, data_directory):
        """Set up the database and store vectorized data."""
        db = chromadb.PersistentClient(path=db_path)
        chroma_collection = db.get_or_create_collection("medical_knowledge")
        vector_store = ChromaVectorStore(chroma_collection=chroma_collection)
        storage_context = StorageContext.from_defaults(vector_store=vector_store)
        if self.changes_detected(data_directory):
            documents = SimpleDirectoryReader(data_directory).load_data()
            chroma_collection.delete(where={})
            self.index = VectorStoreIndex.from_documents(documents, storage_context=storage_context)
        else:
            self.index = VectorStoreIndex.from_vector_store(vector_store)
            print("Data vectorized and stored in the database.")

    def setup_tools(self):
        # Configure function tools for the system
        self.query_engine = self.index.as_query_engine()
        self.get_appointment_state_tool = FunctionTool.from_defaults(fn=self.get_appointment_state)
        self.update_appointment_tool = FunctionTool.from_defaults(fn=self.update_appointment)
        self.create_appointment_tool = FunctionTool.from_defaults(fn=self.create_appointment)
        self.record_diagnosis_tool = FunctionTool.from_defaults(fn=self.record_diagnosis)
        self.medical_diagnosis_tool = QueryEngineTool.from_defaults(
            self.query_engine,
            name="medical_diagnosis",
            description="A RAG engine for retrieving medical information."
        )

    # Retrieves the current state of an appointment based on its ID.
    def get_appointment_state(self, appointment_id: str) -> str:
        try:
            return str(self.appointments[appointment_id].dict())
        except KeyError:
            return f"Appointment ID {appointment_id} not found"

    # Updates a specific property of an appointment.
    def update_appointment(self, appointment_id: str, property: str, value: str) -> str:
        appointment = self.appointments.get(appointment_id)
        if appointment:
            setattr(appointment, property, value)
            return f"Appointment ID {appointment_id} updated with {property} = {value}"
        return "Appointment not found"

    # Creates a new appointment with a unique ID.
    def create_appointment(self, appointment_id: str) -> str:
        self.appointments[appointment_id] = MedicalAppointment()
        return "Appointment created."

    # Records a diagnosis for an appointment after symptoms have been noted.
    def record_diagnosis(self, appointment_id: str, diagnosis: str) -> str:
        appointment: MedicalAppointment = self.appointments.get(appointment_id)
        if appointment and appointment.symptoms:
            appointment.diagnosis = diagnosis
            return f"Diagnosis recorded for Appointment ID {appointment_id}. Diagnosis: {diagnosis}"
        return "Diagnosis cannot be recorded. Please tell me more about your symptoms."

    def setup_agent(self):
        # use MODEL and TEMPERATRE here
        gpt = OpenAI(model=MODEL, temperature=TEMPERATURE)
        self.agent = FunctionCallingAgent.from_tools(
            tools=[
                self.get_appointment_state_tool,
                self.update_appointment_tool,
                self.create_appointment_tool,
                self.record_diagnosis_tool,
                self.medical_diagnosis_tool,
                # self.confirm_appointment_tool
            ],
            llm=gpt,
            prefix_messages=[
                ChatMessage(
                    role="system",
                    # use SYSTEM_PROMPT here
                    content=SYSTEM_PROMPT,
                )
            ],
            max_function_calls=10,
            allow_parallel_tool_calls=False
        )

    def interactive_session(self):
        print("Welcome to the Medical Diagnosis and Booking System!")
        print("Please enter your symptoms or ask about appointment details. Type 'exit' to quit.")

        while True:
            user_input = input("Your query: ")
            if user_input.lower() == 'exit':
                break

            response = self.agent.chat(user_input)
            print("Agent Response:", response.response)

    def chat(self, user_input):
        response = self.agent.chat(user_input)
        return response


if __name__ == "__main__":
    system = MedicalAppointmentSystem(data_directory="./data", db_path="./chroma_db")
    system.interactive_session()