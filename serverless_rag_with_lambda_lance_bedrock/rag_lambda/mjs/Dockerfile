# Use an official Node.js runtime as the base image
#FROM public.ecr.aws/lambda/nodejs:18
FROM public.ecr.aws/amazonlinux/amazonlinux:2023

# Install Node.js (if not already bundled)
RUN yum install -y nodejs npm git

RUN yum install -y glibc

# Set the working directory
WORKDIR /var/task

# Copy package.json and package-lock.json for dependency installation
COPY package.json ./

# Install dependencies
RUN npm install --production

# Copy the application code
COPY index.mjs .

# Set the entrypoint for the Lambda container
CMD ["index.handler"]