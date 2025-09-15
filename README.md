# VocabDict

**A desktop application for vocabulary learning and word translation.**  
*Currently in development.*

---

## 🔍 Overview

VocabDict is a desktop application designed to assist with vocabulary learning by providing translations and usage examples for each distinct sense of a word.
It extracts word data from Wiktionary, uses machine learning models 
to generate translations for senses and example sentences (as they are only available in the original language), and presents all meanings with contextual examples through a Flutter-based frontend.
---

## ⚙️ Features

- **Data Extraction:** Pulls word data from Wiktionary.
- **Translation:** Fetches translations from wiktionary extract, then Uses Transformer models (e.g., NLLB) to generate translations for relevant entries.
- **Contextualization:** Applies Paraphrase MiniLM to filter out incorrect translations with multiple meanings.
- **Frontend:** Displays results in a user-friendly interface built with Flutter.

---

## 🛠️ Technologies Used

- **Backend:** Python (FastAPI)
- **Frontend:** Flutter
- **Machine Learning:** Transformer models (NLLB, Paraphrase MiniLM)

---

# Implementation

## Data Extraction
- Raw data is downloaded from [Kaikki](https://kaikki.org/dictionary/rawdata.html).
- Extracts required for original language, target language, and English (as intermediary).
- Entries indexed by byte-offset and stored in SQLite for **instant lookup**.

## Data Querying & Translation
- Upon word lookup, byte-offsets are retrieved from the database and the relevant data from raw files.
- For each word appearance, we extract:
  - Word, type (noun, verb, etc.), senses, example sentences, translations
- When a direct translation is missing between the original and target language, the English entry is used as an intermediary.
- **Edge cases** (e.g., sense mismatches) are detected using Paraphrase MiniLM to validate semantic similarity.
- Finally, senses and example sentences are machine-translated to the target language using NLLB.

**Example:**  
Looking up the German word "Katze" (en: cat) for Korean:
- Sense 1: common pet cat → direct translation available  
- Sense 2: female cat → no direct translation to korean; English intermediate "queen" mapped incorrectly to "왕비" (Queen, as in female version of king)  
- Paraphrase MiniLM detects semantic mismatch and rejects inaccurate translation

---
## 📝 License

This project is licensed under the MIT License.
