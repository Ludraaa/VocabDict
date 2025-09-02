import requests
import sys
from query import pprint
import time

word = sys.argv[1] if len(sys.argv) > 1 else print("Please provide a word as argument") or exit(1)
tl_model = 'NLLB'
if len(sys.argv) > 2:
    tl_model = sys.argv[2]

query_url = "http://127.0.0.1:8766/query"
payload = {
    "word": word,
    "lang": "de",
    "target_lang": "ko",
    "tl_model": tl_model,
    "debug": False
    }


start_time = time.time()  # record start
response = requests.post(query_url, json=payload)

if response.ok:
    pprint(response.json())
else:
    print("Error:", response.status_code, response.text)

end_time = time.time()  # record end
print(f"Query took {end_time - start_time:.2f} seconds")