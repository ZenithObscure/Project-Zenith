# Android Testing Guide for Project Zenith

## Step 1: Connect Your Android Phone via USB

### Enable Developer Mode on Android
1. Go to **Settings → About Phone**
2. Tap **Build Number** 7 times (status will say "Developer mode enabled")
3. Go back to **Settings → Developer Options**
4. Enable **USB Debugging**
5. Select **File Transfer** mode (not Charging Only)

### Connect via USB Cable
- Plug your Android phone into your Linux computer via USB cable
- You should see a prompt on your phone asking to allow USB debugging
- Tap **Always allow from this computer**

## Step 2: Verify ADB Connection

```bash
# Check if your phone is detected
adb devices

# Output should show:
# List of attached devices
# XXXXXXXXXXXXXXXX device
```

If your device shows as `unauthorized`, tap "Allow" on the phone again.

## Step 3: Deploy Zenith to Your Phone

Once your phone is detected, run:

```bash
cd /home/zenith/Project-Zenith
flutter run
```

Flutter will automatically:
- Build the app for your connected device
- Install it on your phone
- Launch the app
- Enable hot reload for live updates

## Step 4: Test the App

### Initial Sign-In
- Username: **A**
- Password: **A**

### Test Features

#### 1. **Engine Module - Configure AI**
1. Tap the **Engine** card
2. Scroll to **Local LLM (Ollama)** section
3. **Important**: Enter the IP address of your computer (not localhost!)
   - Run on your computer: `hostname -I` to get your IP
   - Example: `http://192.168.1.100:11434`
4. Enable "Run Fidus locally"
5. Tap **Refresh Models** to discover models
6. Select a model from dropdown
7. Tap **Test Local LLM** to verify

#### 2. **Chat with Fidus**
1. Go back to home screen
2. Tap the **Fidus** card
3. Ask questions like:
   - "What is Project Zenith?"
   - "How do I optimize storage?"
   - "Write a Python hello world"
4. Watch AI respond in real-time on your phone!

#### 3. **Local Node Server**
1. In Engine module, scroll to **Local Node Server**
2. Tap **Start Node** to enable P2P inference
3. Note the endpoint displayed
4. Other Tailscale devices can now use your phone as an AI backend!

#### 4. **Tailscale Integration**
- The app will discover other Zenith instances on your Tailscale network
- You can send inference requests to other devices running the app

### Quick Test Flow
```
Home → Engine → Enable Local LLM → Set IP → Refresh Models → Select Model → Test
       → Back to Home → Fidus Chat → Send prompt → See response
       → Back to Engine → Start Node → Share with Tailscale network
```

## Important Network Settings

### Accessing Ollama from Your Phone
Your Ollama runs on your **Linux computer**, not your phone!

**For local network (WiFi):**
- Get your computer's IP: `hostname -I`
- Example: `192.168.1.100:11434`
- Phone must be on same WiFi

**For Tailscale:**
- Install Tailscale on your phone
- Connect both computer and phone to same Tailscale network
- Use Tailscale IP (e.g., `100.x.x.x:11434`)
- Works over internet, not just local network!

## Troubleshooting

### Phone Not Detected by adb
```bash
# Restart adb
adb kill-server
adb devices

# Or try:
adb usb
```

### Ollama Connection Failed
**Error**: "Cannot connect to Ollama at http://..."

1. Verify Ollama is running on your computer:
   ```bash
   ps aux | grep ollama
   ```

2. Use correct IP address of your computer (not 127.0.0.1):
   ```bash
   hostname -I
   ```

3. Both devices must be on same network (WiFi or Tailscale)

4. Check firewall isn't blocking port 11434:
   ```bash
   curl http://YOUR-IP:11434/api/tags
   ```

### Model Not Found
1. Pull the model on your computer:
   ```bash
   ollama pull qwen2.5-coder:1.5b
   ```

2. Verify it exists:
   ```bash
   ollama list
   ```

3. Tap **Refresh Models** in app again

### App Crashes or Won't Start
1. Disconnect phone: `flutter run` will show connection error
2. Uninstall app: `adb uninstall com.example.zenith`
3. Reconnect: `adb devices`
4. Try again: `flutter run`

### Hot Reload Not Working
In the Flutter terminal while app is running:
- `r` - Hot reload (quick, keeps state)
- `R` - Hot restart (full restart, clears state)

## Features to Showcase

1. **Offline AI** - All processing on your devices, no cloud
2. **P2P Network** - Encrypt traffic with Tailscale
3. **Multi-Device** - Ask AI questions from phone, use computer as backend
4. **Local Models** - Full privacy, your data never leaves home network

## Testing Checklist

- [ ] Phone connects via USB (adb devices shows it)
- [ ] App installs and launches
- [ ] Can sign in (A/A)
- [ ] Engine module loads
- [ ] Can set Ollama endpoint to computer's IP
- [ ] Models refresh and show in dropdown
- [ ] Test connection succeeds
- [ ] Can send a prompt to Fidus
- [ ] AI responds with relevant answer
- [ ] Can start local node server
- [ ] Endpoint is displayed

## Next Steps

After successful testing:
1. Try larger models (`qwen2.5-coder:7b`) for better quality
2. Test with Tailscale on another device
3. Try P2P inference between devices
4. Measure response times and battery usage
5. Collect feedback for UI/UX improvements

## Getting Help

If something doesn't work:
1. Check device logs: `adb logcat | grep zenith`
2. Verify computer IP: `hostname -I`
3. Test Ollama manually: `curl http://IP:11434/api/tags`
4. Check Flutter output for specific errors

Good luck testing! 🚀
