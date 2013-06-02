/*
 * Patch ``League of Legends.exe'' by replacing the public key
 * in the executable.
 *
 * You may generate your own RSA2048 key pair by
 *   $ openssl genrsa -out my 2048
 *   $ openssl rsa -in my -pubout > my.pub
 *
 *
 * Robert <robertabcd at gmail.com>
 * 2013/6/2
 */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char *lolpub =
"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1mV8+Ez6EEdQtCYPewmO"
"dhG4ElhApH3AQe1TReKZNHP/uYTQSNE9vAly7W/sXFAJPTUtwXqOeFwMqumzuk3T"
"iXJhQul/zywcBKRawVxgN7qMAdPv7t5AijWh1brDrevdOlwzPwUp24ar96YKDefS"
"73EFnY1xoEqSs1DnkrwKN0Nb8Sjwgs5XrZiLV03U1SlqJD2nHhhLpAAgnKeY6vJN"
"/+H3l/TXfvrbi4b+9GjJkGiahREEvJN2FnKSPofI+gPfA2rXUQTNeSDMYsPhAaV6"
"JPY4iZBpb1//6/p2fTbL1inYDhC5KDuSPPoBHmZFm8gT10jAk1V9fuWeweYAIIve"
"5wIDAQAB";

/* Change this to your public key */
const char *mypub =
"MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAp7H6dxiftfx2YVusyjzU"
"Nj2IVycziBlvlKNyak21ofjRH2Ogej/n+M2skuwKshHKqAcApSC9jaF6gaS67Uhc"
"lHp3yHH1OR8jUUL1sZPK69AlElQyfv8XOMPTKq59viG2k1ta9Xq8vZ1bXlvosJIY"
"L0GryBfsyEQc+VGRhzGhrEXgaRiizlHF0rQGd2NAVZ4v8/lp3lQ+7rVRT9ji6qCm"
"BCI+lKEWy/DL7zwaRYV8crgiXll5Y9xYZnmVxag3USvOWmLVVRuLRq9i280iO7pJ"
"jmppXNv4prmmIDyqjgk0ML3GPCrh2Y11o5QPnCT7Dlj+QuYunKGOFJPRawly/0ax"
"QwIDAQAB";

int *build_table(const char *data, int len) {
	int *t = (int *) calloc(len, sizeof(int));
	int i = 2, m = 0;
	while (i < len) {
		if (data[i - 1] == data[m])
			t[i++] = ++m;
		else if (m > 0)
			m = t[m];
		else
			t[i++] = 0;
	}
	return t;
}

int match(const char *data, int dlen, const char *patt, int plen) {
	int *t = build_table(patt, plen);
	int i = 0, m = 0;
	while (i < dlen) {
		if (data[i] == patt[m]) {
			i++;
			if (++m == plen)
				break;
		} else if (m > 0) {
			m = t[m];
		} else {
			i++;
		}
	}
	free(t);
	return m == plen ? i - m : dlen;
}

int main(int argc, char *argv[]) {
	assert(sizeof(lolpub) == sizeof(mypub));

	if (argc != 2) {
		fprintf(stderr, "Usage: %s <executable>\n", argv[0]);
		return 1;
	}

	FILE *fp;
	int size;
	char *buffer;

	// load the file
	if ((fp = fopen(argv[1], "rb")) == NULL) {
		perror("Cannot open executable");
		return 1;
	}

	fseek(fp, 0, SEEK_END);
	size = ftell(fp);
	fseek(fp, 0, SEEK_SET);

	if ((buffer = (char *) malloc(size)) == NULL) {
		fprintf(stderr, "Cannot allocate memory\n");
		return 1;
	}

	if (fread(buffer, size, 1, fp) != 1) {
		fprintf(stderr, "Cannot read file\n");
		return 1;
	}

	fclose(fp);

	// find key
	int pos = match(buffer, size, lolpub, strlen(lolpub));

	if (pos >= size) {
		fprintf(stderr, "Cannot find pattern\n");
		return 1;
	}

	printf("Public key at %d\n", pos);

	// make a backup
	char *backupfn = (char *) malloc(strlen(argv[1]) + 10);
	strcpy(backupfn, argv[1]);
	strcat(backupfn, ".bak");
	if ((fp = fopen(backupfn, "wb")) == NULL) {
		fprintf(stderr, "Cannot open backup file for writing\n");
		return 1;
	}
	if (fwrite(buffer, size, 1, fp) != 1) {
		fprintf(stderr, "Cannot write to backup file\n");
		return 1;
	}
	fclose(fp);

	// replace key
	memcpy(buffer + pos, mypub, strlen(lolpub));

	// save
	if ((fp = fopen(argv[1], "wb")) == NULL) {
		fprintf(stderr, "Cannot save patched file\n");
		return 1;
	}
	if (fwrite(buffer, size, 1, fp) != 1) {
		fprintf(stderr, "Cannot write to patched file\n");
		return 1;
	}
	fclose(fp);

	return 0;
}
