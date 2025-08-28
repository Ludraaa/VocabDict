import sys
import json
import sqlite3
from tqdm import tqdm

path_map = {
        'de' : './wiktionary/de_dict.jsonl'
        }


db = sqlite3.connect('./wiktionary/offsets.db')
cur = db.cursor()


#returns data from all entries of a word
def query(word, lang, target_lang, debug = False):

    #fetch all entries of <word> from db
    cur.execute(f"SELECT offset FROM " + lang + "_offsets WHERE word =?", (word,))

    #get all line offsets of actual jsonl file
    lines = cur.fetchall()
    
    #object to be returned later
    ret = {}
    #original word
    ret[lang] = word

    #open appropriate language file
    with open(path_map[lang], 'rb') as f:

        #for every offset matching our query
        for _i in tqdm(lines, desc='Querying ' + lang + '_dict..'):

            #unpack _i, as it is a tuple with 1 entry
            i = _i[0]

            #reset pointer to start of file
            f.seek(0)

            #go to offset and read
            f.seek(i)
            line = f.readline()
            
            #print(line.decode("utf-8"))

            #load as json and decode from binary
            entry = json.loads(line.decode("utf-8"))
            
            #if the entries language is not german, skip
            if entry.get('lang_code') != lang:
                continue


            #create empty dict from this entry
            ret[i] = {}
            
            if debug:
                print(entry.keys())
                #print(entry)

            #word type/position
            ret[i]['type'] = entry.get('pos')


            #iterate over all senses
            senses = entry.get('senses')
            ret[i]['senses'] = {}
            for j, sense in enumerate(senses):

                #iterate over all glosses and add to return
                glosses = sense.get('glosses')
                    ret[i]['senses'][j + 1] = glosses

            #get translations
            translations = entry.get('translations', [])
             
            #init dicts for translations
            ret[i][target_lang] = {}

            #fallback, as many words might not have a translation
            ret[i]['en'] = {}
            
            #for translations via english dict
            ret[i]['en_to_' + target_lang] = {}

            for tl in translations:

                sense_id = tl.get('sense_index')

                #always get english translations as well
                for target in (target_lang, 'en'):

                    if tl.get('lang_code') == target:
                    
                        ret[i][target].setdefault(sense_id, []).append(tl.get('word'))

                
                #get target language translations over english as well, as many words in german dont have korean translartions
                if tl.get('lang_code') == 'en':

                    en_results = en_lookup(tl.get('word'), target_lang)
                    for result in en_results:
                        ret[i]['en_to_'+target_lang].setdefault(sense_id, []).append(result)


    return ret

#takes the english translation and returns the word in target_language, by going through the english dictionary
def en_lookup(word, target_lang):
    
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
                    if tl.get('word') in ret:
                        continue

                    ret.append(tl.get('word'))

        ####################################################
        #TODO
        #implement embedding check to compare simarity of
        #english and korean translation to the original
        #german sense

        #using sentence-transformers

        """
        from sentence-transformers import SentenceTransformer, utils

        #this should probably be somewhere outside
        sentence_trans = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')

        sense = #german sense
        word = #english or korean (probably this is better) word from dictionary

        s_vec = sentence_trans.encode(sense, convert_to_tensor=True)
        w_vec = sentence_trans.encode(word, convert_to_tensor=True)

        similarity = utils.cos_sim(s_vec, w_vec).item()

        threshold = [0...1], probably 0.7 or so
        
        if similarity > threshold:
            include word
        

        """

        return ret


#pretty json printer by wrapping json.dumps()
def pprint(j):
    print(json.dumps(j, indent=2, ensure_ascii=False))





model = "later"
tokenizer = "later"


def marian_translate(word):
    return word



word = sys.argv[1].lower()
debug = False

if len(sys.argv) > 2:
    debug = sys.argv[2]

lang = 'de'
target_lang = 'ko'

result = query(word, lang, target_lang, debug)

pprint(result)
