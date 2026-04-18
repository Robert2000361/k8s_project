# Stage 1: Build
FROM node:18-alpine AS builder
WORKDIR /usr/src/app

# Copy package files and install dependencies
COPY package*.json ./
# استخدمنا npm install بدلاً من npm ci لعدم وجود package-lock.json
RUN npm install --omit=dev

# Copy application code
COPY . .

# Stage 2: Production
FROM node:18-alpine
WORKDIR /usr/src/app

# Copy from builder stage
COPY --from=builder /usr/src/app ./

# Set environment variable
ENV NODE_ENV=production

# Use the built-in non-root user "node" (UID: 1000)
USER node
EXPOSE 3000

CMD ["node", "app.js"]