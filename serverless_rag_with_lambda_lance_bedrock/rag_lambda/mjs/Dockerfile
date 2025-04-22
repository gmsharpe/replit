FROM public.ecr.aws/amazonlinux/amazonlinux:2023

# Install Node.js 18
RUN dnf install -y nodejs npm git

# Set the working directory
WORKDIR /var/task

# Copy and install dependencies
COPY package*.json ./

# Copy application code
COPY index.mjs .

# Optional: Confirm glibc version
RUN ldd --version

# Set the Lambda handler
CMD ["index.handler"]
