

import asyncio
import websockets
import logging
import json
import random
from typing import List, Dict


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


HOST = "localhost"
PORT = 8765

class WebSocketServer:


    def __init__(self):
        self.connected_clients = set()

    async def handler(self, websocket, path):


        logger.info(f"Client connected: {websocket.remote_address}")
        self.connected_clients.add(websocket)

        try:
            async for message in websocket:
                data = json.loads(message)
                logger.info(f"Received message: {data}")

                await websocket.send(json.dumps(data))
        except websockets.exceptions.ConnectionClosed as e:
            logger.warning(f"Client disconnected: {websocket.remote_address} ({e})")
        finally:
            self.connected_clients.remove(websocket)

    async def broadcast(self, message: Dict[str, str]):


        if self.connected_clients:
            message_str = json.dumps(message)
            await asyncio.wait([client.send(message_str) for client in self.connected_clients])
            logger.info("Broadcast message to all clients.")

    async def start_server(self):


        server = await websockets.serve(self.handler, HOST, PORT)
        logger.info(f"WebSocket Server started on ws://{HOST}:{PORT}")
        await server.wait_closed()

class WebSocketClient:


    def __init__(self, uri: str):
        self.uri = uri

    async def connect(self):


        async with websockets.connect(self.uri) as websocket:
            logger.info("Connected to the WebSocket server.")

            message = {
                "action": "greet",
                "content": "Hello, server!"
            }
            logger.info(f"Sending message: {message}")
            await websocket.send(json.dumps(message))


            response = await websocket.recv()
            logger.info(f"Received response: {response}")
            
    async def send_messages(self, messages: List[Dict[str, str]]):


        async with websockets.connect(self.uri) as websocket:
            for message in messages:
                logger.info(f"Sending message: {message}")
                await websocket.send(json.dumps(message))


                response = await websocket.recv()
                logger.info(f"Received response: {response}")

async def main():


    server = WebSocketServer()
    server_task = asyncio.ensure_future(server.start_server())
    await asyncio.sleep(1)


    client = WebSocketClient(f"ws://{HOST}:{PORT}")
    client_task = asyncio.ensure_future(client.connect())


    await client_task


    for _ in range(5):
        message = {
            "action": "broadcast",
            "content": f"Random number: {random.randint(1, 100)}"
        }
        await server.broadcast(message)
        await asyncio.sleep(2)

    server_task.cancel()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except asyncio.CancelledError:
        logger.info("Server shutdown gracefully.")

