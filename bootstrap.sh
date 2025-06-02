# Copy RAG database to PVC
cp /.llama/temp/aap_faiss_store.db /.llama/data/distributions/ansible-chatbot

# Start llama-stack server
python -m llama_stack.distribution.server.server --config /.llama/distributions/ansible-chatbot/ansible-chatbot-run.yaml
