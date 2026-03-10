# AI Testing Guide for Project Zenith

## Overview
Project Zenith now has a fully functional AI chat interface powered by Ollama local LLM.

## Prerequisites

### 1. Ollama Installation
```bash
# Check if Ollama is installed
ollama --version

# If not installed:
curl -fsSL https://ollama.ai/install.sh | sh
```

### 2. Start Ollama Service
```bash
# Start Ollama (if not running)
ollama serve

# Or check if already running
ps aux | grep ollama
```

### 3. Pull a Model
```bash
# Small model for testing (1.5GB)
ollama pull qwen2.5-coder:1.5b

# Better model for coding (4.7GB)
ollama pull qwen2.5-coder:7b

# General purpose model (2GB)
ollama pull llama3.2:3b

# List installed models
ollama list
```

## Testing the AI in Zenith

### 1. Run the App
```bash
cd /home/zenith/Project-Zenith
flutter run -d linux
```

### 2. Sign In
- Username: `A`
- Password: `A`

### 3. Navigate to Engine Module
1. Click on the **Engine** card in the home page
2. Scroll down to **Local LLM (Ollama)** section
3. Enable **"Run Fidus locally"**
4. Verify endpoint: `http://127.0.0.1:11434`
5. Click **"Refresh Models"** to discover available models
6. Select a model from the dropdown (e.g., `qwen2.5-coder:1.5b`)
7. Click **"Test Local LLM"** to verify connection

### 4. Chat with Fidus
1. Click on the **Fidus** card in the home page
2. Try the quick prompts:
   - "Optimize my storage setup"
   - "Recommend engine settings for AI coding"
   - "Give me a full Zenith status report"
3. Or type your own questions!

### 5. Features to Test

#### Conversation Management
- Send multiple messages to build conversation history
- Click the **trash icon** to clear conversation
- Verify responses maintain context from previous messages

#### Error Handling
- Stop Ollama (`killall ollama`) and try sending a message
  - Should show helpful error with fix instructions
- Restart Ollama and retry

#### Model Selection
- Try different models
- Compare response quality and speed
- Smaller models (1.5b, 3b) are faster but less accurate
- Larger models (7b+) are slower but more capable

#### UI Features
- **Auto-scroll**: Messages automatically scroll to bottom
- **Selectable text**: You can copy AI responses
- **Loading indicators**: Shows thinking state during generation
- **Model display**: Current model shown in header

## Testing P2P Inference (Tailscale)

### 1. Start Local Node Server
1. In Engine module, scroll to **Local Node Server**
2. Click **"Start Node"** to start HTTP server on port 8080
3. Note the endpoint (e.g., `http://192.168.1.100:8080`)

### 2. Test Health Endpoint
```bash
# From another device on your tailnet
curl http://YOUR-TAILSCALE-IP:8080/health
```

### 3. Test Inference Endpoint
```bash
curl -X POST http://YOUR-TAILSCALE-IP:8080/generate \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "What is Project Zenith?",
    "history": []
  }'
```

## Troubleshooting

### Ollama Not Found
```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Add to PATH if needed
export PATH=$PATH:/usr/local/bin
```

### Model Loading Slow
- Ollama loads models on first use
- Subsequent requests are faster
- Use smaller models for testing

### Connection Refused
```bash
# Check Ollama is running
systemctl status ollama  # or
ps aux | grep ollama

# Check endpoint
curl http://127.0.0.1:11434/api/tags
```

### Empty Responses
- Some models need specific prompts
- Try different wording
- Check model is fully downloaded: `ollama list`

## Performance Tips

1. **Model Selection**:
   - `qwen2.5-coder:1.5b` - Fast, good for testing (1GB)
   - `qwen2.5-coder:7b` - Best for coding (4.7GB)
   - `llama3.2:3b` - Fast general purpose (2GB)

2. **System Resources**:
   - 8GB RAM minimum for 3b models
   - 16GB RAM recommended for 7b models
   - SSD storage for faster loading

3. **Conversation Length**:
   - Longer conversations = slower responses
   - Clear conversation to reset context
   - System prompt adds ~200 tokens per request

## Next Steps

- [ ] Test streaming responses (real-time generation)
- [ ] Add markdown rendering for formatted responses
- [ ] Save/load conversation transcripts
- [ ] Multi-model selection in chat UI
- [ ] Temperature and parameter controls
- [ ] Token usage tracking
