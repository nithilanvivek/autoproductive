import json
import subprocess
import sys

component = sys.argv[1]
for value, operation, expected in [
    ('Straße', 'uppercase', 'STRASSE'),
    ('  a\n', 'trim', 'a'),
    ('z\na', 'sortLines', 'a\nz'),
    ('a\na\nb', 'uniqueLines', 'a\nb'),
    ('already fine', 'unknown', 'already fine'),
]:
    result = subprocess.run([component], input=json.dumps({'text': value, 'operation': operation}).encode(), capture_output=True, check=True)
    assert json.loads(result.stdout)['text'] == expected
result = subprocess.run([component], input=b'not json', capture_output=True)
assert result.returncode != 0 and b'not json' not in result.stderr
print('Passed 6 optional clipboard component checks.')
