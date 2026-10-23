#!/usr/bin/env python3
"""
Continuity Ecosystem - Optional E2E Encrypted Relay Server
Allows paired Android and macOS clients to exchange encrypted frames
across different subnets without breaking end-to-end encryption.
"""

import asyncio
import json
import logging
import sys
from typing import Dict, Set

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

class RelayServer:
    def __init__(self, host: str = "0.0.0.0", port: int = 8765):
        self.host = host
        self.port = port
        self.rooms: Dict[str, Set[asyncio.StreamWriter]] = {}

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        peer_addr = writer.get_extra_info("peername")
        logging.info(f"Connected client: {peer_addr}")
        current_room = None

        try:
            while True:
                # Read 4-byte big-endian length prefix
                length_bytes = await reader.read(4)
                if not length_bytes or len(length_bytes) < 4:
                    break
                length = int.from_bytes(length_bytes, byteorder="big")
                if length <= 0 or length > 16 * 1024 * 1024:
                    logging.warning(f"Invalid frame size: {length}")
                    break

                payload = await reader.readexactly(length)

                # Inspect first packet for room join: {"action":"join", "room_token":"<token>"}
                if current_room is None:
                    try:
                        join_msg = json.loads(payload.decode("utf-8"))
                        if join_msg.get("action") == "join" and "room_token" in join_msg:
                            current_room = join_msg["room_token"]
                            if current_room not in self.rooms:
                                self.rooms[current_room] = set()
                            self.rooms[current_room].add(writer)
                            logging.info(f"Client {peer_addr} joined room {current_room[:8]}...")
                            continue
                    except Exception:
                        pass

                # Forward raw encrypted frame to all other peers in the room
                if current_room and current_room in self.rooms:
                    for peer in list(self.rooms[current_room]):
                        if peer != writer:
                            try:
                                peer.write(length_bytes + payload)
                                await peer.drain()
                            except Exception:
                                self.rooms[current_room].discard(peer)

        except asyncio.IncompleteReadError:
            pass
        except Exception as e:
            logging.error(f"Error handling client {peer_addr}: {e}")
        finally:
            logging.info(f"Client disconnected: {peer_addr}")
            if current_room and current_room in self.rooms:
                self.rooms[current_room].discard(writer)
                if not self.rooms[current_room]:
                    del self.rooms[current_room]
            writer.close()
            await writer.wait_closed()

    async def start(self):
        server = await asyncio.start_server(self.handle_client, self.host, self.port)
        logging.info(f"📡 Continuity Relay Server listening on {self.host}:{self.port}")
        async with server:
            await server.serve_forever()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    server = RelayServer(port=port)
    try:
        asyncio.run(server.start())
    except KeyboardInterrupt:
        logging.info("Relay server stopped.")
