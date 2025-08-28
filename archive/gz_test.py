import gzip
import json
import sys
from tqdm import tqdm


def query(word):

    #open the file
    with gzip.open('./wiktionary/de_dict.jsonl.gz', 'rt', encoding='utf-8') as f:

        #iterate through the file
        for i, line in tqdm(enumerate(f)):
            entry = json.loads(line)
        
            #check whether the entry has a word field
            if 'word' not in entry.keys():
                print('Entry without word..')
                continue
            #check if the word matches our query
            if entry['word'].lower() == word.lower():
                return  process_entry(entry)

def process_entry(entry):
    print(entry)





word = sys.argv[1]
query(word)
