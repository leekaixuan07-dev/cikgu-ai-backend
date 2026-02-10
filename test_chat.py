import requests
import json

url = "http://127.0.0.1:8000/chat"
payload = {
    "uid": "test_user",
    "message": "Hello",
    "current_chapter_name": "Bab 1"
}
headers = {
    "Content-Type": "application/json"
}

try:
    response = requests.post(url, json=payload, headers=headers)
    print(f"Status Code: {response.status_code}")
    print(f"Response: {response.text}")
except Exception as e:
    print(f"Request failed: {e}")
