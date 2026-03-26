
  export SWITCHBOT_KEY_ID=92
  export SWITCHBOT_ENC_KEY=4cc89c5ff0317e9b1649e05de9a6b487

  cd nixos/hydra/switchbot
pip install -r requirements.txt

# Step 1 — get the encryption key (needs your SwitchBot account + the MAC from the SwitchBot app)
./get-encryption-key AA:BB:CC:DD:EE:FF your@email.com

# Step 2 — use it
./switchbot-lock -d AA:BB:CC:DD:EE:FF -k <KEY_ID> -e <ENC_KEY> status
./switchbot-lock -d AA:BB:CC:DD:EE:FF -k <KEY_ID> -e <ENC_KEY> lock
./switchbot-lock -d AA:BB:CC:DD:EE:FF -k <KEY_ID> -e <ENC_KEY> unlock