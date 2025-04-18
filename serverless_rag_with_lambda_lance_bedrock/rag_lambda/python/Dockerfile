# Use an official Python runtime as the base image
FROM public.ecr.aws/lambda/python:3.11

# Set the working directory
WORKDIR /var/task

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY index.py .

# Set the entrypoint for the Lambda container
CMD ["index.handler"]
