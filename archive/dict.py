import json
import sys
from tqdm import tqdm

lang_map = {
            'en' : './wiktionary/en_dict.jsonl',
            'de' : './wiktionary/de_dict.jsonl',
            'kr' : './wiktionary/kr_dict.jsonl'
        }

length_map = {
        'en' : 1403716,
        'de' : 357017,
        'kr' : 1
        }

def dictionary_lookup(word, lang, target_lang, debug=False):
    file_length = 0

    #json to be returned
    ret = {}
    ret[lang] = word

    with open(lang_map[lang], 'r', encoding='utf-8') as f:
        #Iterate over every word in the dictionary (given by line)
        for i, line in tqdm(enumerate(f), total=length_map[lang]):
            
            file_length = i
            entry = json.loads(line)

            #check if entry has 'word'
            if 'word' not in entry.keys():
                continue

            #Check if the entry matches the query
            if entry['word'].lower()  == word.lower():
                #get word type (e.g. noun, verb)
                position = entry['pos']
                
                if debug:
                    print(entry)

                #create inner dict for meanings, keyed by entry id
                ret[i] = {}
                ret[i]['pos'] = position
                
                #get gender and quick forms if word is noun
                if position == 'noun':
                    head = entry['head_templates']
                    gender = head[0]['args']['1'][0]
                    quick_forms = head[0]['args']['1'][2:]
                    
                    #append to inner dict
                    ret[i]['gender'] = gender
                    ret[i]['quick_forms'] = quick_forms
                    
                #Check if entry has a 'translation' key
                if 'translations' in entry.keys():

                    translations = entry['translations']
                    #Check for the target language translation
                    for translation in translations:
                        if translation['code'] == target_lang:

                            trans_word = translation['word']
                            trans_sense = translation['sense']

                            if trans_sense in ret[i].keys():
                                ret[i][sense].append(trans_word)
                            else:
                                ret[i][sense] = [trans_word]
                else:
                    #Check whether the key senses exists (en)
                    if 'senses' in entry.keys():
                        senses = entry['senses']

                        #Check for every different sense
                        for j, sense in enumerate(senses):
                
                            #Check if sense contains translations (en)
                            if 'translations' in sense.keys():
                                translations = sense['translations']
                                #Check for the target language translation
                                for translation in translations:
                                    if translation['code'] == target_lang:
                                        
                                        trans_word = translation['word']
                                        trans_sense = translation['sense']
                                        if trans_sense in ret[i]:
                                            ret[i][trans_sense].append(trans_word)
                                        else:
                                            ret[i][trans_sense] = [trans_word]
                                        
                            #check if sense contains glosses (de)
                            #translation (in english)
                            meanings = sense['glosses']

                            key = j

                            #usage category
                            if 'topics' in sense.keys():
                                
                                key = str(sense['topics'])[1:-2]

                            elif 'raw_tags' in sense.keys():
                                
                                key = str(sense['raw_tags'])[1:-2]
                                
                            #init list if not existing
                            if key not in ret[i].keys():
                                ret[i][key] = []
                            
                            #append special chars 'RFX', if the verb is reflexive in german
                            if 'tags' in sense:
                                if 'reflexive' in sense['tags']:
                                    ret[i][key].insert(0, 'RFX')

                            #append meanings
                            for m in meanings:
                                ret[i][key].append(m)

                    else:
                        print('Whether translation nor senses found..')

    print('File length: ' + str(file_length))

    return ret
            


word = str(sys.argv[1])
#lang = str(sys.argv[1])
#target_lang = str(sys.argv[2])
debug = False

if len(sys.argv) > 2:
    debug = sys.argv[2]

obj = dictionary_lookup(word, 'de', 'en', debug=debug)
print(obj)

