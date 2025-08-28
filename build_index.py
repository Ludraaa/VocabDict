import json
import sys
import sqlite3
from tqdm import tqdm


lang = sys.argv[1] #e.g. 'de', 'en'

db = sqlite3.connect("./wiktionary/offsets.db")
cur = db.cursor()

#create table
cur.execute(f"CREATE TABLE IF NOT EXISTS {lang}_offsets (word TEXT,offset INTEGER)")

#define table index
cur.execute(f"CREATE INDEX IF NOT EXISTS word_index ON {lang}_offsets(word)")


#builds the index list for the given jsonl wiktextract
def build(path):
    with open(path, 'rb') as f:
        
        #total offset in bytes
        offset = 0

        #iterate over all lines
        for i, line in enumerate(f):

            #load json from line
            entry = json.loads(line.decode("utf-8"))
            
            word = entry.get('word', '*notdefined*').lower()

            #inserts word and offset into db
            cur.execute(f"INSERT INTO {lang}_offsets VALUES (?, ?)", (word, offset))
            
            #add offset
            offset += len(line)



build(f"./wiktionary/{lang}_dict.jsonl")

db.commit()
db.close()
