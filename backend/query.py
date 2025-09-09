import sys
import json
import sqlite3
from tqdm import tqdm
from fastapi import FastAPI
from pydantic import BaseModel

#run this app with:
"""
uvicorn query:app --reload --host 127.0.0.1 --port 8766
"""


app = FastAPI()

# Request schema
class QueryRequest(BaseModel):
    word: str
    lang: str
    target_lang: str
    tl_model: str = "NLLB"
    debug: bool = False


path = './wiktionary/*_dict.jsonl'


#returns data from all entries of a word
def fetch(word, lang, target_lang, cur, debug = False):

    #fetch all entries of <word> from db
    cur.execute(f"SELECT offset FROM " + lang + "_offsets WHERE word =?", (word,))

    #get all line offsets of actual jsonl file
    lines = cur.fetchall()
    
    #object to be returned later
    ret = {}
    #original word
    ret[lang] = word


    #open appropriate language file
    with open(path.replace('*', lang), 'rb') as f:

        #for every offset matching our query
        for _i in tqdm(lines, desc=f"Querying {word} in {lang} dictionary..."):

            #unpack _i, as it is a tuple with 1 entry
            i = _i[0]

            #reset pointer to start of file
            f.seek(0)

            #go to offset and read
            f.seek(i)
            line = f.readline()

            #load as json and decode from binary
            entry = json.loads(line.decode("utf-8"))
            
            #if the entries language is not german, skip
            if entry.get('lang_code') != lang:
                continue

            #create empty dict from this entry
            ret[i] = {}

            if debug:
                print(entry.keys())
                print(entry)

            #word type/position
            ret[i]['type'] = entry.get('pos')
            #get the original word as well 

            #TODO handle things like articles ("der", "die", "das") in german and capitalization in english
            ret[i]['word'] = entry.get('word')

            #iterate over all senses
            senses = entry.get('senses', [])
            ret[i]['senses'] = {}

            for j, sense in enumerate(senses):

                id = sense.get('sense_index')

                #initialize empty dict
                ret[i]['senses'][id] = {}

                #iterate over all glosses and add to return
                glosses = sense.get('glosses', [])
                for gloss in glosses:
                    ret[i]['senses'][id][lang] = gloss

                    #get translation
                    ret[i]['senses'][id][target_lang] = gloss
                
                #get raw tags as simple categories, if they exist (rare)
                ret[i]['senses'][id]['tags'] = sense.get('raw_tags', [])

                #get example sentences

                for k, example in enumerate(sense.get('examples', [])):
                    ret[i]['senses'][id].setdefault(lang + '_ex', []).append(example.get('text'))

                    #translate to target_lang as well
                    ret[i]['senses'][id].setdefault(target_lang + '_ex', []).append(example.get('text'))
                


            #get translations
            translations = entry.get('translations', [])
             
            #init dicts for translations
            ret[i]['tl'] = {}
            tl_dict = ret[i]['tl']

            tl_dict[target_lang] = {}
            

            #fallback, as many words might not have a direct translation to target_lang
            tl_dict['en'] = {}
            
            #for translations via english dict
            tl_dict['en_to_' + target_lang] = {}

            for tl in translations:

                sense_id = tl.get('sense_index')

                #always get english translations as well
                for target in (target_lang, 'en'):

                    #check, if the translation matches our language and only add new translations, no duplicates
                    if tl.get('lang_code') == target and tl.get('word') not in tl_dict[target].get(sense_id, []):
                    
                        tl_dict[target].setdefault(sense_id, []).append(tl.get('word'))

                
                #get target language translations over english as well, as many words in german dont have korean translations
                if tl.get('lang_code') == 'en':

                    en_results = en_lookup(tl.get('word'), target_lang, ret[i]['senses'][sense_id][lang], cur)
                    for result in en_results:

                        #check, whether the translation matches the original sense
                        scores = similarity_check([[ret[lang], ret[i]['senses'][sense_id][lang], result]], [ret[i]['senses'][sense_id][lang]])


                        if scores[0][1] < 0.3: #sense similarity threshold
                            print(f"Refused '{result}' as translation for sense '{ret[i]['senses'][sense_id][lang]}' with score {scores[0][1]}")
                            continue

                        if result not in tl_dict['en_to_' + target_lang].get(sense_id, []):
                            tl_dict['en_to_'+target_lang].setdefault(sense_id, []).append(result)


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
                if content == target_lang + '_ex':

                    for idx, ex in enumerate(dict[entry]['senses'][sense_id][content]):

                        to_be_translated.append(ex)
                        origin.append([entry, "senses", sense_id, content, idx])
        

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

# load the open router api key
def load_OR_key(path="OR_key.txt"):
    with open(path, "r") as f:
        return f.read().strip()

openrouter_api_key = load_OR_key(path="OR_key.txt")
openrouter_url = "https://openrouter.ai/api/v1/chat/completions"
model_id = "deepseek/deepseek-r1:free"  


#translates the list of strings using deepseek
def deepseek_translate(words, lang, target_lang):
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



@app.post("/query")
def query(request: QueryRequest):

    print("Querying for word:", request.word)

    word = request.word.lower()
    lang = request.lang
    target_lang = request.target_lang
    tl_model = request.tl_model
    debug = request.debug

    with sqlite3.connect('./wiktionary/offsets.db') as db:
        cur = db.cursor()

        #Fetch initial data
        result1 = fetch(word, lang, target_lang, cur, debug)

        #Collect everything that needs to be translated, with their origin paths
        to_be_translated, origins = collect_to_be_translated(result1, lang, target_lang)

        #Translate everything that needs to be translated
        translated = []

        match tl_model:
            case "NLLB":
                translated = nllb_translate(to_be_translated, lang, target_lang)
            case "Deepseek":
                translated = deepseek_translate(to_be_translated, lang, target_lang)
        

        #Reinsert translations back into original dict
        result2 = insert_translations(translated, origins, result1, lang, target_lang)

    #return finished json object
    return result2