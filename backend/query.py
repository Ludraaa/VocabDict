import sys
import json
import sqlite3
from tqdm import tqdm
from fastapi import Body, FastAPI, Path, WebSocket, WebSocketDisconnect, HTTPException, Header
from pydantic import BaseModel
import asyncio
from contextlib import asynccontextmanager
from jose import jwt, JWTError
from datetime import datetime, timedelta, timezone
from argon2 import PasswordHasher

#run this app with:
"""
uvicorn query:app --reload --host 127.0.0.1 --port 8766
"""

#to verify and decode jwt tokens
def decode_jwt(token: str):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms="HS256")
        return payload.get("user_id")
    except JWTError:
        return None

def verify_user_token(authorization: str):
    try:
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Missing or invalid token")

        token = authorization.split(" ")[1]
        user_id = decode_jwt(token)
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token")
    
        # Check user exists
        conn = sqlite3.connect(DB_FILE)
        cur = conn.cursor()
        cur.execute("SELECT id FROM users WHERE id = ?", (user_id,))
        if not cur.fetchone():
            raise HTTPException(status_code=401, detail="User does not exist")
        conn.close()

        return user_id
    
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")
    
    return user_id


app = FastAPI()

path = './wiktionary/*_dict.jsonl'

# load the open router (or any) api key
def load_OR_key(path="OR_key.txt"):
    with open(path, "r") as f:
        return f.read().strip()

SECRET_KEY = load_OR_key(path="jwt_key.txt")
DB_FILE = "vocab_data.sqlite"

@asynccontextmanager
async def lifespan(app: FastAPI):
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # Users
    cur.execute("""
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
    """)

    # Collections (top-level)
    cur.execute("""
    CREATE TABLE IF NOT EXISTS collections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id)
            ON DELETE CASCADE
    )
    """)

    # Chapters / Units
    cur.execute("""
    CREATE TABLE IF NOT EXISTS chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        collection_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (collection_id) REFERENCES collections(id)
            ON DELETE CASCADE
    )
    """)

    # Vocabulary
    cur.execute("""
    CREATE TABLE IF NOT EXISTS vocab (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chapter_id INTEGER NOT NULL,
    data TEXT NOT NULL,              -- JSON blob
    name TEXT NOT NULL,              -- Display name
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (chapter_id) REFERENCES chapters(id)
        ON DELETE CASCADE
    )    
    """)

    conn.commit()
    conn.close()
    yield

app = FastAPI(lifespan=lifespan)

ph = PasswordHasher()
class UserCreate(BaseModel):
    username: str
    password: str

class UserLogin(BaseModel):
    username: str
    password: str

def create_token(user_id: int):
    payload = {
        "user_id": user_id,
        "exp": datetime.now(timezone.utc) + timedelta(days=1)
    }
    return jwt.encode(payload, SECRET_KEY, algorithm="HS256")

def get_user_by_username(username: str):
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()
    cur.execute("SELECT id, username, password_hash FROM users WHERE username = ?", (username,))
    row = cur.fetchone()
    conn.close()
    return row  # returns (id, username, password_hash) or None

@app.post("/register")
def register(user: UserCreate):
    print("Registering user:", user.username)
    print("Password (plain):", user.password)
    if get_user_by_username(user.username):
        raise HTTPException(status_code=400, detail="Username already exists, please login instead.")

    # Use argon2 to hash the password
    password_hash = ph.hash(user.password)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO users (username, password_hash) VALUES (?, ?)",
        (user.username, password_hash)
    )
    conn.commit()
    conn.close()
    
    return {"status": "ok"}

@app.post("/login")
def login(user: UserLogin):
    db_user = get_user_by_username(user.username)
    if not db_user:
        raise HTTPException(status_code=401, detail="Invalid username or password")
    
    user_id, username, password_hash = db_user
    if not ph.verify(password_hash, user.password):
        raise HTTPException(status_code=401, detail="Invalid username or password")
    
    token = create_token(user_id)
    print("User logged in:", user.username)
    print("Generated token:", token)
    return {"token": token}



#############Collection stuff##############

@app.get("/collections")
def get_collections(authorization: str = Header(None)):
    user_id = verify_user_token(authorization)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    cur.execute(
        "SELECT id, name FROM collections WHERE user_id = ? ORDER BY created_at",
        (user_id,)
    )
    rows = cur.fetchall()
    conn.close()

    return [{"id": r[0], "name": r[1]} for r in rows]

# Pydantic model for POST body
class CollectionCreate(BaseModel):
    name: str

@app.post("/createCollection")
def create_collection(
    collection: CollectionCreate,
    authorization: str = Header(None)
):
    user_id = verify_user_token(authorization)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO collections (user_id, name) VALUES (?, ?)",
        (user_id, collection.name)
    )
    conn.commit()
    new_id = cur.lastrowid
    conn.close()

    return {"id": new_id, "name": collection.name}

class RenameRequest(BaseModel):
    new_name: str

@app.patch("/collections/{collection_id}")
def rename_collection(
    collection_id: int = Path(...),
    payload: RenameRequest = ...,
    authorization: str = Header(None)
):
    user_id = verify_user_token(authorization)

    print("Renaming collection:", collection_id, "to", payload.new_name)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # Ensure collection belongs to user
    cur.execute(
        "SELECT id FROM collections WHERE id = ? AND user_id = ?",
        (collection_id, user_id)
    )
    row = cur.fetchone()
    print(row)
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Collection not found")

    # Update name
    cur.execute(
        "UPDATE collections SET name = ? WHERE id = ?",
        (payload.new_name, collection_id)
    )
    conn.commit()
    conn.close()

    return {"id": collection_id, "new_name": payload.new_name}


@app.delete("/collections/{collection_id}")
def delete_collection(
    collection_id: int = Path(...),
    authorization: str = Header(None)
):
    user_id = verify_user_token(authorization)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # Check ownership
    cur.execute(
        "SELECT id FROM collections WHERE id = ? AND user_id = ?",
        (collection_id, user_id)
    )
    row = cur.fetchone()
    if not row:
        conn.close()
        raise HTTPException(status_code=404, detail="Collection not found")

    # Delete collection (optional: cascade delete chapters/vocab if needed)
    cur.execute("DELETE FROM collections WHERE id = ?", (collection_id,))
    conn.commit()
    conn.close()

    return {"status": "deleted", "id": collection_id}

#############Chapter stuff##############

@app.get("/collections/{collection_id}/chapters")
def get_chapters(collection_id: int, authorization: str = Header(None)):
    user_id = verify_user_token(authorization)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # Ensure collection belongs to user
    cur.execute("SELECT id FROM collections WHERE id = ? AND user_id = ?", (collection_id, user_id))
    if not cur.fetchone():
        conn.close()
        raise HTTPException(status_code=404, detail="Collection not found")

    cur.execute("SELECT id, name FROM chapters WHERE collection_id = ?", (collection_id,))
    chapters = [{"id": row[0], "name": row[1]} for row in cur.fetchall()]
    conn.close()
    return chapters


@app.post("/collections/{collection_id}/chapters")
def create_chapter(collection_id: int, authorization: str = Header(None), body: dict = Body(...)):
    user_id = verify_user_token(authorization)

    name = body.get("name")
    if not name:
        raise HTTPException(status_code=400, detail="Name required")

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # Ensure collection belongs to user
    cur.execute("SELECT id FROM collections WHERE id = ? AND user_id = ?", (collection_id, user_id))
    if not cur.fetchone():
        conn.close()
        raise HTTPException(status_code=404, detail="Collection not found")

    cur.execute("INSERT INTO chapters (collection_id, name) VALUES (?, ?)", (collection_id, name))
    conn.commit()
    conn.close()
    return {"status": "created", "name": name}

@app.patch("/chapters/{chapter_id}")
def rename_chapter(chapter_id: int, authorization: str = Header(None), body: dict = Body(...)):
    user_id = verify_user_token(authorization)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()
    # Ensure chapter belongs to a collection owned by user
    cur.execute("""
        SELECT c.id
        FROM chapters c
        JOIN collections co ON c.collection_id = co.id
        WHERE c.id = ? AND co.user_id = ?
    """, (chapter_id, user_id))

    if not cur.fetchone():
        conn.close()
        raise HTTPException(status_code=404, detail="Chapter not found")
    
    new_name = body.get("new_name")

    cur.execute("UPDATE chapters SET name = ? WHERE id = ?", (new_name, chapter_id))
    conn.commit()
    conn.close()
    return {"status": "updated", "name": new_name}


@app.delete("/chapters/{chapter_id}")
def delete_chapter(chapter_id: int, authorization: str = Header(None)):
    user_id = verify_user_token(authorization)  # validate JWT

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # Ensure chapter belongs to a collection owned by this user
    cur.execute("""
        SELECT c.id
        FROM chapters c
        JOIN collections co ON c.collection_id = co.id
        WHERE c.id = ? AND co.user_id = ?
    """, (chapter_id, user_id))

    if not cur.fetchone():
        conn.close()
        raise HTTPException(status_code=404, detail="Chapter not found")

    cur.execute("DELETE FROM chapters WHERE id = ?", (chapter_id,))
    conn.commit()
    conn.close()
    return {"status": "deleted", "id": chapter_id}

#############Vocab stuff##############

@app.get("/chapters/{chapter_id}/vocab")
def get_vocab(chapter_id: int, authorization: str = Header(None)):
    user_id = verify_user_token(authorization)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # Ensure chapter belongs to user
    cur.execute("""
        SELECT c.id
        FROM chapters c
        JOIN collections co ON c.collection_id = co.id
        WHERE c.id = ? AND co.user_id = ?
    """, (chapter_id, user_id))

    if not cur.fetchone():
        conn.close()
        raise HTTPException(status_code=404, detail="Chapter not found")

    # Fetch vocab entries
    cur.execute("SELECT id, name FROM vocab WHERE chapter_id = ?", (chapter_id,))
    vocab = [{"id": row[0], "name": row[1]} for row in cur.fetchall()]

    conn.close()
    return vocab

@app.post("/chapters/{chapter_id}/vocab")
def create_vocab(chapter_id: int, authorization: str = Header(None), body: dict = Body(...)):
    """
    body should contain:
    {
        "name": "display name",
        "data": { ... }  # your giant JSON
    }
    """
    user_id = verify_user_token(authorization)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # Ensure chapter belongs to user
    cur.execute("""
        SELECT c.id
        FROM chapters c
        JOIN collections co ON c.collection_id = co.id
        WHERE c.id = ? AND co.user_id = ?
    """, (chapter_id, user_id))

    if not cur.fetchone():
        conn.close()
        raise HTTPException(status_code=404, detail="Chapter not found")

    name = body.get("name")
    data = json.dumps(body.get("data", {}))  # store as JSON string

    cur.execute(
        "INSERT INTO vocab (chapter_id, name, data) VALUES (?, ?, ?)",
        (chapter_id, name, data)
    )
    conn.commit()
    vocab_id = cur.lastrowid
    conn.close()

    return {"status": "created", "id": vocab_id, "name": name}

@app.put("/chapters/{chapter_id}/vocab/{vocab_id}")
def update_vocab(
    chapter_id: int,
    vocab_id: int,
    authorization: str = Header(None),
    body: dict = Body(...)
):
    """
    Update an existing vocab entry.
    body should contain:
    {
        "name": "display name",
        "data": { ... }  # giant JSON
    }
    """
    if authorization is None:
        raise HTTPException(status_code=401, detail="Authorization header missing")

    user_id = verify_user_token(authorization)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # Ensure chapter belongs to user
    cur.execute("""
        SELECT c.id
        FROM chapters c
        JOIN collections co ON c.collection_id = co.id
        WHERE c.id = ? AND co.user_id = ?
    """, (chapter_id, user_id))

    if not cur.fetchone():
        conn.close()
        raise HTTPException(status_code=404, detail="Chapter not found or not owned by user")

    name = body.get("name")
    data = json.dumps(body.get("data", {}))

    # Make sure vocab exists
    cur.execute("""
        SELECT id FROM vocab
        WHERE id = ? AND chapter_id = ?
    """, (vocab_id, chapter_id))
    if not cur.fetchone():
        conn.close()
        raise HTTPException(status_code=404, detail="Vocab entry not found")

    # Update
    cur.execute("""
        UPDATE vocab
        SET name = ?, data = ?
        WHERE id = ? AND chapter_id = ?
    """, (name, data, vocab_id, chapter_id))

    conn.commit()
    conn.close()

    return {"status": "updated", "id": vocab_id, "name": name}



@app.delete("/vocab/{vocab_id}")
def delete_vocab(
    vocab_id: int,
    authorization: str = Header(None),
):
    user_id = verify_user_token(authorization)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # Ensure vocab belongs to the user
    cur.execute("""
        SELECT v.id
        FROM vocab v
        JOIN chapters c ON v.chapter_id = c.id
        JOIN collections co ON c.collection_id = co.id
        WHERE v.id = ? AND co.user_id = ?
    """, (vocab_id, user_id))

    if cur.fetchone() is None:
        conn.close()
        raise HTTPException(status_code=404, detail="Vocab not found")

    cur.execute("DELETE FROM vocab WHERE id = ?", (vocab_id,))
    conn.commit()
    conn.close()

    return {"status": "deleted"}


@app.get("/vocab_data/{chapter_id}/{vocab_id}")
def get_vocab_data(chapter_id: int, vocab_id: int, authorization: str = Header(None)):
    if authorization is None:
        raise HTTPException(status_code=401, detail="Authorization header missing")

    user_id = verify_user_token(authorization)

    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()

    # Make sure the chapter belongs to the user
    cur.execute("""
        SELECT c.id
        FROM chapters c
        JOIN collections co ON c.collection_id = co.id
        WHERE c.id = ? AND co.user_id = ?
    """, (chapter_id, user_id))
    chapter = cur.fetchone()
    if not chapter:
        conn.close()
        raise HTTPException(status_code=403, detail="Chapter not found or not owned by user")

    # Fetch vocab entry
    cur.execute("""
        SELECT id, chapter_id, name, data, created_at
        FROM vocab
        WHERE id = ? AND chapter_id = ?
    """, (vocab_id, chapter_id))
    vocab = cur.fetchone()
    conn.close()

    if not vocab:
        raise HTTPException(status_code=404, detail="Vocab not found")

    vocab_dict = {
        "id": vocab[0],
        "chapter_id": vocab[1],
        "name": vocab[2],
        "data": vocab[3],  # JSON blob as string
        "created_at": vocab[4],
    }
    return vocab_dict








#############Query stuff##############

#returns data from all entries of a word
def fetch(word, lang, target_lang, cur, debug = False):

    #fetch all entries of <word> from db
    cur.execute(f"SELECT offset FROM " + lang + "_offsets WHERE word =?", (word,))

    #get all line offsets of actual jsonl file
    lines = cur.fetchall()
    
    #object to be returned later
    ret = {}

    #open appropriate language file
    with open(path.replace('*', lang), 'rb') as f:

        #for every offset matching our query
        for _i in tqdm(lines, desc=f"Querying {word} in {lang} dictionary..."):

            #unpack _i, as it is a tuple with 1 entry
            entry_id = _i[0]

            #reset pointer to start of file
            f.seek(0)

            #go to offset and read
            f.seek(entry_id)
            line = f.readline()

            #load as json and decode from binary
            entry = json.loads(line.decode("utf-8"))
            
            #if the entries language is not german, skip
            if entry.get('lang_code') != lang:
                continue

            #create empty dict from this entry
            ret[entry_id] = {}

            if debug:
                print(entry.keys())
                print(entry)

            #original word
            #TODO handle things like articles ("der", "die", "das") in german and capitalization in english
            ret[entry_id]['word'] = entry.get('word')

            #word type/position
            ret[entry_id]['type'] = entry.get('pos')
            
            #iterate over all senses
            senses = entry.get('senses', [])
            ret[entry_id]['senses'] = {}

            for j, sense in enumerate(senses):

                id = sense.get('sense_index')

                #initialize empty dict
                ret[entry_id]['senses'][id] = {}

                #iterate over all glosses and add to return
                glosses = sense.get('glosses', [])
                for gloss in glosses:
                    ret[entry_id]['senses'][id][lang] = gloss

                    #get translation
                    ret[entry_id]['senses'][id][target_lang] = gloss
                
                #get raw tags as simple categories, if they exist (rare)
                ret[entry_id]['senses'][id]['tags'] = sense.get('raw_tags', [])

                #get example sentences
                ret[entry_id]['senses'][id].setdefault('ex', {})

                for k, example in enumerate(sense.get('examples', [])):
                    ret[entry_id]['senses'][id]['ex'].setdefault(k, {})[lang] = example.get('text')
                
                    #translate to target_lang as well
                    ret[entry_id]['senses'][id]['ex'].setdefault(k, {})[target_lang] = example.get('text')
                
            #initialize translation dicts:
            #for sense in ret[i]['senses']:
            #    ret[i]['senses'][sense][f'{lang}_tl'] = []
            #    ret[i]['senses'][sense]['en_tl'] = []

            #get translations
            translations = entry.get('translations', [])
             
            #init dicts for translations
            tl_dict = {}
            tl_dict[target_lang] = {}
            
            #fallback, as many words might not have a direct translation to target_lang
            tl_dict['en'] = {}
            

            for tl in translations:

                sense_id = tl.get('sense_index')

                #always get english translations as well
                for target in (target_lang, 'en'):

                    #check, if the translation matches our language and only add new translations, no duplicates
                    if tl.get('lang_code') == target and tl.get('word') not in tl_dict[target].get(sense_id, []):
                    
                        tl_dict[target].setdefault(sense_id, []).append(tl.get('word'))

                
                #get target language translations over english as well, as many words in german dont have korean translations
                if tl.get('lang_code') == 'en':

                    en_results = en_lookup(tl.get('word'), target_lang, ret[entry_id]['senses'][sense_id][lang], cur)
                    for result in en_results:

                        #check, whether the translation matches the original sense
                        scores = similarity_check([[ret[entry_id]['word'], ret[entry_id]['senses'][sense_id][lang], result]], [ret[entry_id]['senses'][sense_id][lang]])


                        if scores[0][1] < 0.3: #sense similarity threshold
                            print(f"Refused '{result}' as translation for sense '{ret[entry_id]['senses'][sense_id][lang]}' with score {scores[0][1]}")
                            continue

                        if result not in tl_dict[target_lang].get(sense_id, []) and result is not None:
                            tl_dict[target_lang].setdefault(sense_id, []).append(result)


            #add translations to return dict
            for sense in ret[entry_id]['senses']:
                ret[entry_id]['senses'][sense][f'{target_lang}_tl'] = tl_dict[target_lang].get(sense, [])
                ret[entry_id]['senses'][sense]['en_tl'] = tl_dict['en'].get(sense, [])
    return ret



#takes the english translation and returns the word in target_language, by going through the english dictionary
def en_lookup(word, target_lang, sense, cur):
    
    #get offsets of entries about word
    cur.execute("SELECT offset FROM en_offsets WHERE word=?", (word,))

    lines = cur.fetchall()

    #open dict file
    with open('./wiktionary/en_dict.jsonl', 'rb') as f:
        
        #list containing all translations to be returned
        ret = []

        for _i in lines:
            #unpack tuple to get int byte offset
            i = _i[0]

            #jump to byte offset and read line
            f.seek(0)
            f.seek(i)

            line = f.readline()

            #convert line to json obj(entry)
            entry = json.loads(line.decode("utf-8"))
            

            #skip non-english entries
            if entry.get('lang_code') != 'en':
                continue
            
            #get all translations
            translations = entry.get('translations', [])
            

            #iterate over all translations and pick ones matching our target_lang
            for tl in translations:
                if tl.get('code') == target_lang:
                    #skip duplicates
                    if tl.get('word') not in ret:
                        ret.append(tl.get('word'))

        return ret



#pretty json printer by wrapping json.dumps()
def pprint(j):
    print(json.dumps(j, indent=2, ensure_ascii=False))


def collect_to_be_translated(dict, lang, target_lang):
    #object containing everything that needs to be translated
    to_be_translated = []
    origin = []

    #Iterate through all different entries associated with the original word
    for entry in dict.keys():

        #skip original word entry
        if entry == lang:
            continue

        #Iterate through all senses of the entry
        for sense_id in dict[entry]['senses'].keys():
            
            for content in dict[entry]['senses'][sense_id]:
                #definitions in target lang
                if content == target_lang:

                    to_be_translated.append(dict[entry]['senses'][sense_id][content])
                    origin.append([entry, "senses", sense_id, content])
                
                #example sentences in target lang
                if content == 'ex':
                    for idx in dict[entry]['senses'][sense_id][content].keys():
                            to_be_translated.append(dict[entry]['senses'][sense_id][content][idx][target_lang])
                            origin.append([entry, "senses", sense_id, content, idx, target_lang])
        

    return to_be_translated, origin




from transformers import AutoTokenizer, AutoModelForSeq2SeqLM
import torch

lang_code_map = {
    "de": "deu_Latn",  # German
    "ko": "kor_Hang",  # Korean
    "en": "eng_Latn",  # English
    "fr": "fra_Latn",  # French
    "es": "spa_Latn",  # Spanish
    # add more as needed
}

#translates the list of words from lang to target_lang using NLLB distilled model
def nllb_translate(words, lang, target_lang):

    if not words:
        print("No words to translate.")
        return []

    #Check for unsupported language codes (to be added as needed)
    if lang not in lang_code_map or target_lang not in lang_code_map:
        raise ValueError(f"Unsupported lang code. Supported: {list(lang_code_map.keys())}")
    
    #get appropriate src and tgt codes from lang_code_map
    src = lang_code_map[lang]
    tgt = lang_code_map[target_lang]

    #load model and tokenizer
    model_name = "facebook/nllb-200-distilled-600M"
    tokenizer = AutoTokenizer.from_pretrained(model_name, src_lang=src, tgt_lang=tgt)
    model = AutoModelForSeq2SeqLM.from_pretrained(model_name)
    model.to('cuda' if torch.cuda.is_available() else 'cpu')

    #tokenize and translate
    inputs = tokenizer(words, return_tensors="pt", padding=True, truncation=True).to(model.device)
    translated = model.generate(**inputs, forced_bos_token_id=tokenizer.convert_tokens_to_ids(tgt))

    return tokenizer.batch_decode(translated, skip_special_tokens=True)


import requests

openrouter_api_key = load_OR_key(path="OR_key.txt")
openrouter_url = "https://openrouter.ai/api/v1/chat/completions"
model_id = "deepseek/deepseek-r1:free"  


#translates the list of strings using deepseek
def deepseek_translate(words, lang, target_lang):
    if not words:
        print("No words to translate.")
        return []
     
    headers = {
        "Authorization": f"Bearer {openrouter_api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": "http://localhost",
        "User-Agent": "VocabDict/1.0 (luisdrayer@web.de)"
    }

    system_role = "You are a translation tool."

    prompt = {
        "role": "user",
        "content": (
            f"Translate the following {lang} sentences into {target_lang}. "
            f"Return the result strictly as a JSON object with keys 'original' and 'translation' "
            f"for each sentence, like:\n"
            f"[{{'original': '...', 'translation': '...'}}, ...]\n\n"
            f"Sentences:\n{words}"
        )
    }

    payload = {
        "model": model_id,
        "messages": [
            {"role": "system", "content": system_role},
            prompt,
        ],
    }

    #try to query deepseek, if it fails (e.g. rate limit), use nllb as backup
    try:
        resp = requests.post(openrouter_url, headers=headers, json=payload)
        resp.raise_for_status()
        content_str = resp.json()["choices"][0]["message"]["content"]
    
        resp = requests.post(openrouter_url, headers=headers, json=payload)
        resp.raise_for_status()
        content_str = resp.json()["choices"][0]["message"]["content"]
        # parse JSON safely
        try:
            content_list = json.loads(content_str.replace("'", '"'))
            return [item["translation"] for item in content_list]
        except json.JSONDecodeError:
            print("DeepSeek returned invalid JSON, falling back to backup translator.")
            return nllb_translate(words, lang, target_lang)

    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 429:
            print("DeepSeek rate-limited (429). Using backup translator...")
            return nllb_translate(words, lang, target_lang)


# load the DeepL api key
def load_DeepL_key(path="DeepL_key.txt"):
    with open(path, "r") as f:
        return f.read().strip()

DeepL_api_key = load_DeepL_key()
DeepL_url = "https://api-free.deepl.com/v2/translate"

#translates the list of strings using DeepL
def deepl_translate(words, lang, target_lang):
    if not words:
        print("No words to translate.")
        return []
    
    headers = {
        "Authorization": f"DeepL-Auth-Key {DeepL_api_key}"
    }

    # DeepL requires multiple 'text' fields for multiple sentences
    data = [("text", w) for w in words]  # list of tuples
    data += [
        ("source_lang", lang),
        ("target_lang", target_lang)
    ]

    resp = requests.post(DeepL_url, headers=headers, data=data)
    resp.raise_for_status()
    #pprint(resp.json())
    return [t["text"] for t in resp.json()["translations"]]




#reinserts the translated elements back into the original dict
def insert_translations(translated, origins, dict, lang, target_lang):
    #iterate through all origins and insert the corresponding translation
    for idx, path in enumerate(origins):

        #start from root of dict
        curr = dict

        #walk along the path to the target element
        for street in path[: -1]:
            curr = curr[street]
        
        #we have arrived at our target element
        #replace the target element with the translation
        curr[path[-1]] = translated[idx]

    return dict



from sentence_transformers import SentenceTransformer, util
#embedding model for semantic similarity checks

embedder = SentenceTransformer('sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2')


#computes similarity scores between all sentence pairs in sentences, using sentence-transformers
def similarity_check(pairs, senses):

    #return object
    cosine_scores = []

    #iterate over all pairs of original word and proposed translation
    for i, pair in enumerate(pairs):

        #list containing all embeddings
        embeddings = []

        #iterate over elements in pair (original word, translation)
        for element in pair:

            #Guard against empty elements
            if element == None:
                continue

            #Compute embedding for both lists
            embeddings.append(embedder.encode(element, convert_to_tensor=True))
        
        #also encode the original sense for comparison
        embeddings.append(embedder.encode(senses[i], convert_to_tensor=True))


        #Compute cosine-similarities---------------------------------------------------

        #compare original word to translation
        translation_sim_score = util.pytorch_cos_sim(embeddings[0], embeddings[1])[0][0].item()

        #compare translation to sense
        sense_sim_score = util.pytorch_cos_sim(embeddings[1], embeddings[2])[0][0].item()

        cosine_scores.append([translation_sim_score, sense_sim_score])

    return cosine_scores


#checks the usage limit of the openrouter key
@app.post("/check_deepseek_key")
def check_openrouter_key():
    headers = {
    "Authorization": f"Bearer {openrouter_api_key}",
    "User-Agent": "VocabDict/1.0 (luisdrayer@web.de)"
    }
    resp = requests.get("https://openrouter.ai/api/v1/key", headers=headers)
    resp.raise_for_status()
    return resp.json()


def append_add_keys(obj, parent=None, key_in_parent=None):
    if isinstance(obj, dict):
        for k, v in list(obj.items()):
            obj[k] = append_add_keys(v, obj, k)

        # If dict is empty, replace it with {"add": {}}
        if not obj:  
            obj["add"] = {}
        
        # If this dict itself lives under an int-like key -> put "add" on parent
        if is_int_key(key_in_parent):
            if isinstance(parent, dict):
                parent["add"] = {}

        return obj

    elif isinstance(obj, list):
        for i in range(len(obj)):
            obj[i] = append_add_keys(obj[i], obj, i)
        obj.append("add")
        return obj

    else:
        return obj
    
def is_int_key(key):
    """
    Check if a given key can be parsed into an integer.

    Parameters:
        key (any): The key to be checked.

    Returns:
        bool: True if the key can be parsed into an integer, False otherwise.
    """
    try:
        int(key)
        return True
    except (ValueError, TypeError):
        return False

#completely wipes a result dict, leaving only keys
def wipe(data):
    if isinstance(data, dict):
        return {k: wipe(v) for k, v in data.items()}
    elif isinstance(data, list):
        return []  # replace lists with empty list
    elif isinstance(data, str):
        return ""  # replace strings with empty string
    else:
        return data  # leave numbers, bools, None unchanged


@app.get("/get_empty_entry")
#gets an empty entry to be used for custom input (by the user)
def get_empty_entry(lang : str, target_lang : str):
    with sqlite3.connect('./wiktionary/offsets.db') as db:
        cur = db.cursor()

        res = append_add_keys(wipe(fetch("herrje", lang, target_lang, cur)))
        val = list(res.values())[0]
    return {"custom": val}

async def run_query(ws: WebSocket, word, lang, target_lang, tl_model):
    await ws.send_text(f"Querying for word: {word}")
    word = word.lower()

    with sqlite3.connect('./wiktionary/offsets.db') as db:
        cur = db.cursor()

        await ws.send_text("Fetching word data")
        result1 = fetch(word, lang, target_lang, cur)

        await ws.send_text(f"Translating entries using {tl_model} model")
        to_be_translated, origins = collect_to_be_translated(result1, lang, target_lang)
        translated = []

        match tl_model:
            case "NLLB":
                translated = nllb_translate(to_be_translated, lang, target_lang)
            case "Deepseek":
                translated = deepseek_translate(to_be_translated, lang, target_lang)
            case "DeepL":
                translated = deepl_translate(to_be_translated, lang, target_lang)

        await ws.send_text("Inserting translations")
        result2 = insert_translations(translated, origins, result1, lang, target_lang)
        append_add_keys(result2)
        pprint(result2)

    await ws.send_json({"type": "result", "data": result2})

@app.websocket("/ws/query")
async def query_ws(ws: WebSocket):
    await ws.accept()
    task = None

    try:
        data = await ws.receive_json()
        word = data["word"]
        lang = data["lang"]
        target_lang = data["target_lang"]
        tl_model = data["tl_model"]

        # Run the query as a cancellable task
        task = asyncio.create_task(run_query(ws, word, lang, target_lang, tl_model))
        await task

        await ws.close()

    except WebSocketDisconnect:
        print("Client disconnected")
        if task:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                print("Query task cancelled successfully")