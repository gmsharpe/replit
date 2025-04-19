# Use an official Node.js runtime as the base image
FROM public.ecr.aws/lambda/nodejs:18

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