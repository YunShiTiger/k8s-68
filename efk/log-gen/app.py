import json
import random
import string
import time

i = 1
with open('./info.log', 'w', encoding='utf8') as f:
    while 1:
        demo = json.dumps({"ip": i, 'time': time.time(), 'rand': random.choice(string.printable, )})
        print(demo)
        f.write(demo + '\n')
        f.flush()
        time.sleep(random.random())
        i += 1
