# 'make secrets.py.cast5' to encrypt, 'make secrets.py' to decrypt.

%: %.cast5
	-echo "make: (Ignore the 'circular dependencies' warning message.  They are harmless.)"
	-echo "make: (If I was better at 'make', I could suppress them.)"
	openssl cast5-cbc -d -in "$<" -out "$@"

%.cast5: %
	-echo "make: (Ignore the 'circular dependencies' warning message.  They are harmless.)"
	-echo "make: (If I was better at 'make', I could suppress them.)"
	openssl cast5-cbc -e -in "$<" -out "$@"

# We can suppress the 'circular deps' warnings for "Makefile", at least.
# (make often has implicit deps on Makefile, which is why this helps.)
Makefile %Makefile: ;
