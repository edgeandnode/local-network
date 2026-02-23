FROM python:3.12-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir fastapi uvicorn

# Copy the mock service
COPY iisa_mock.py ./

EXPOSE 8080

CMD ["uvicorn", "iisa_mock:app", "--host", "0.0.0.0", "--port", "8080"]
