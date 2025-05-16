# Use lightweight Node.js base image
FROM node:20-slim AS builder

ARG RPC_URL
ENV VITE_RPC_URL=$RPC_URL

# Set working directory
WORKDIR /app

# Install required packages
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Clone esplr repo
RUN git clone https://github.com/paulmillr/esplr ./

# Install dependencies and build the static site
RUN npm ci && npm run build


# ---------- Final image ----------
FROM node:20-slim AS runner

WORKDIR /app

# Install a minimal static file server
RUN npm install -g serve

# Copy the built output from the builder stage
COPY --from=builder /app/dist /app/dist

# Expose the port the static server will use
EXPOSE 3000

# Serve the static site
CMD ["serve", "-s", "dist", "-l", "3000"]
