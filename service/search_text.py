"""Display-search words: punctuation and ampersands never become query syntax."""
import re


def words(value):
    return re.findall(r'[^\W_]+',str(value or '').casefold().replace('&',' and '))


def matches_words(value,query):
    haystack=words(value)
    return all(any(word.startswith(token)for word in haystack)for token in words(query))


def register_search(connection):
    connection.create_function('l2g_words',2,lambda value,query:int(matches_words(value,query)),deterministic=True)
    connection.create_function('l2g_prefix',2,lambda value,query:int(' '.join(words(value)).startswith(' '.join(words(query)))),deterministic=True)
