FROM python:3.11-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim AS runtime
WORKDIR /app
COPY --from=builder /install /usr/local
COPY core/ ./core/
COPY labs/ ./labs/
RUN useradd -r -s /bin/false agentuser
USER agentuser
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "print('ok')"
ENV PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["python", "-m", "core.agent_base"]
