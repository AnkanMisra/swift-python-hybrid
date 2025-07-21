

from flask import Flask, jsonify, request
from flask_cors import CORS
import logging
from typing import Dict, Any


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


app = Flask(__name__)
CORS(app)


database = {
    1: {'name': 'Alice', 'age': 30},
    2: {'name': 'Bob', 'age': 25},
    3: {'name': 'Charlie', 'age': 35}
}


def find_user(user_id: int) -> Dict[str, Any]:
    return database.get(user_id, None)

@app.route('/users', methods=['GET'])
def get_users():

    logger.info("Fetching all users.")
    return jsonify(database), 200

@app.route('/users/<int:user_id>', methods=['GET'])
def get_user(user_id):

    user = find_user(user_id)
    if user:
        logger.info(f"User found: ID {user_id}")
        return jsonify(user), 200
    else:
        logger.warning(f"User not found: ID {user_id}")
        return jsonify({'error': 'User not found'}), 404

@app.route('/users', methods=['POST'])
def create_user():

    if request.is_json:
        new_data = request.get_json()
        user_id = max(database.keys()) + 1
        database[user_id] = new_data
        logger.info(f"User created with ID {user_id}: {new_data}")
        return jsonify({'id': user_id}), 201
    else:
        logger.warning("Invalid data format.")
        return jsonify({'error': 'Request must be JSON'}), 400

@app.route('/users/<int:user_id>', methods=['PUT'])
def update_user(user_id):

    if request.is_json:
        new_data = request.get_json()
        if user_id in database:
            database[user_id].update(new_data)
            logger.info(f"User updated: ID {user_id}: {new_data}")
            return jsonify(database[user_id]), 200
        else:
            logger.warning(f"User not found for update: ID {user_id}")
            return jsonify({'error': 'User not found'}), 404
    else:
        logger.warning("Invalid data format for update.")
        return jsonify({'error': 'Request must be JSON'}), 400

@app.route('/users/<int:user_id>', methods=['DELETE'])
def delete_user(user_id):

    if user_id in database:
        deleted_user = database.pop(user_id)
        logger.info(f"User deleted: ID {user_id}")
        return jsonify(deleted_user), 200
    else:
        logger.warning(f"User not found for deletion: ID {user_id}")
        return jsonify({'error': 'User not found'}), 404


if __name__ == '__main__':
    app.run(debug=True)

