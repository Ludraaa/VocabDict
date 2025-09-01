import requests
import sys
from query import pprint

word = sys.argv[1] if len(sys.argv) > 1 else print("Please provide a word as argument") or exit(1)

url = "http://127.0.0.1:8765/query"
payload = {
    "word": word,
    "lang": "ko",
    "target_lang": "de",
    "debug": False
    }

response = requests.post(url, json=payload)

if response.ok:
    pprint(response.json())
else:
    print("Error:", response.status_code, response.text)
