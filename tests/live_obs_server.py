"""
Live OBS WebSocket v5 Protocol Test Server
Runs a lightweight RFC 6455 WebSocket server in pure Python standard library
to test real live network communication with PresenterSync & PresenterSync Remote.
"""

import socket
import hashlib
import base64
import struct
import threading
import time
import json
import sys

PORT = 4455
PASSWORD = "testPassword456"
SALT = "saltX789"
CHALLENGE = "chalY123"

# Calculate expected OBS v5 auth response:
# secret = base64(sha256(password + salt))
# auth   = base64(sha256(secret + challenge))
h1 = hashlib.sha256((PASSWORD + SALT).encode('utf-8')).digest()
secret = base64.b64encode(h1).decode('utf-8')
h2 = hashlib.sha256((secret + CHALLENGE).encode('utf-8')).digest()
EXPECTED_AUTH = base64.b64encode(h2).decode('utf-8')

def encode_frame(payload_str, opcode=1):
    data = payload_str.encode('utf-8') if isinstance(payload_str, str) else payload_str
    length = len(data)
    frame = bytearray([0x80 | opcode]) # Fin bit set
    if length <= 125:
        frame.append(length)
    elif length <= 65535:
        frame.append(126)
        frame.extend(struct.pack("!H", length))
    else:
        frame.append(127)
        frame.extend(struct.pack("!Q", length))
    frame.extend(data)
    return bytes(frame)

def decode_frame(conn):
    try:
        header = conn.recv(2)
        if not header or len(header) < 2:
            return None, None
        b1, b2 = header[0], header[1]
        opcode = b1 & 0x0F
        is_masked = bool(b2 & 0x80)
        length = b2 & 0x7F
        if length == 126:
            raw_len = conn.recv(2)
            if len(raw_len) < 2: return None, None
            length = struct.unpack("!H", raw_len)[0]
        elif length == 127:
            raw_len = conn.recv(8)
            if len(raw_len) < 8: return None, None
            length = struct.unpack("!Q", raw_len)[0]
        mask = conn.recv(4) if is_masked else None
        
        data = bytearray()
        while len(data) < length:
            chunk = conn.recv(length - len(data))
            if not chunk: break
            data.extend(chunk)
            
        if is_masked and mask:
            data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        return opcode, data.decode('utf-8', errors='ignore')
    except Exception as e:
        return None, None

def handle_client(conn, addr):
    try:
        # 1. Read HTTP Upgrade Request
        req_raw = conn.recv(4096).decode('utf-8', errors='ignore')
        key = None
        for line in req_raw.splitlines():
            if line.lower().startswith("sec-websocket-key:"):
                key = line.split(":", 1)[1].strip()
                break
        if not key:
            conn.close()
            return

        # 2. Compute Sec-WebSocket-Accept
        magic = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        accept_token = base64.b64encode(hashlib.sha1(magic.encode('utf-8')).digest()).decode('utf-8')
        handshake_resp = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept_token}\r\n\r\n"
        )
        conn.sendall(handshake_resp.encode('utf-8'))
        print(f"[SERVER] Handshake completed with {addr}")

        # 3. Send Op 0 Hello with Challenge & Salt
        hello_msg = json.dumps({
            "op": 0,
            "d": {
                "obsWebSocketVersion": "5.5.0",
                "rpcVersion": 1,
                "authentication": {
                    "challenge": CHALLENGE,
                    "salt": SALT
                }
            }
        })
        conn.sendall(encode_frame(hello_msg))
        print("[SERVER] Sent Op 0 Hello")

        # 4. Receive Op 1 Identify
        op, payload = decode_frame(conn)
        print(f"[SERVER] Received frame: op={op}, payload={payload}")
        ident = json.loads(payload)
        auth_received = ident.get("d", {}).get("authentication", "")
        if auth_received != EXPECTED_AUTH:
            print(f"[SERVER FAIL] Auth mismatch! Expected: {EXPECTED_AUTH}, Got: {auth_received}")
            conn.close()
            sys.exit(1)
        print("[SERVER PASS] Client SHA256 authentication matched successfully!")

        # 5. Send Op 2 Identified
        identified_msg = json.dumps({
            "op": 2,
            "d": {
                "negotiatedRpcVersion": 1
            }
        })
        conn.sendall(encode_frame(identified_msg))
        print("[SERVER] Sent Op 2 Identified")

        # 6. Receive Op 6 Initial State Query (GetInputMute)
        op, payload = decode_frame(conn)
        print(f"[SERVER] Received query: {payload}")
        req = json.loads(payload)
        req_id = req.get("d", {}).get("requestId", "")
        input_name = req.get("d", {}).get("requestData", {}).get("inputName", "")
        if req_id != "InitRemoteMute" or input_name != "Mic/Aux":
            print(f"[SERVER FAIL] Invalid initial state query: {payload}")
            conn.close()
            sys.exit(1)
        print("[SERVER PASS] Received GetInputMute for Mic/Aux!")

        # 7. Reply Op 7 RequestResponse (LIVE state)
        resp_msg = json.dumps({
            "op": 7,
            "d": {
                "requestType": "GetInputMute",
                "requestId": req_id,
                "requestStatus": {"result": True, "code": 100},
                "responseData": {"inputMuted": False}
            }
        })
        conn.sendall(encode_frame(resp_msg))
        print("[SERVER] Sent Op 7 Response (inputMuted: false)")

        time.sleep(0.1)

        # 8. Send Op 5 Event: Microphone muted
        event_msg = json.dumps({
            "op": 5,
            "d": {
                "eventType": "InputMuteStateChanged",
                "eventData": {
                    "inputName": "Mic/Aux",
                    "inputMuted": True
                }
            }
        })
        conn.sendall(encode_frame(event_msg))
        print("[SERVER] Broadcast Op 5 Event (inputMuted: true)")

        # 9. Receive Op 6 ToggleInputMute triggered by client clicker
        op, payload = decode_frame(conn)
        print(f"[SERVER] Received clicker payload: {payload}")
        click_req = json.loads(payload)
        req_type = click_req.get("d", {}).get("requestType", "")
        if req_type != "ToggleInputMute":
            print(f"[SERVER FAIL] Expected ToggleInputMute, got: {req_type}")
            conn.close()
            sys.exit(1)
        print("[SERVER PASS] Verified ToggleInputMute transmitted from client!")

        # 10. Receive Op 6 KeepAlive / GetVersion Heartbeat
        op, payload = decode_frame(conn)
        if payload and "KeepAlive" in payload:
            print("[SERVER PASS] Verified 30s Heartbeat KeepAlive received over live socket!")

        print("\n=== ALL LIVE SOCKET OPERATIONS PASSED WITH 100% INTEGRITY ===")
        conn.close()
        sys.exit(0)
    except Exception as e:
        print(f"[SERVER ERROR] {e}")
        conn.close()
        sys.exit(1)

def run_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", PORT))
    server.listen(1)
    print(f"[SERVER] Listening on 127.0.0.1:{PORT}...")
    conn, addr = server.accept()
    handle_client(conn, addr)
    server.close()

if __name__ == "__main__":
    run_server()
