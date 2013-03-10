#include <stdint.h>

// All integers are stored in little-endian.

struct rofl_header {
    uint8_t magic[6]; // RIOT \0 \0
    uint8_t signature[256];
    uint16_t header_length; // 0x120
    uint32_t file_length;
    uint32_t metadata_offset; // 0x120
    uint32_t metadata_length;
    uint32_t payload_header_offset;
    uint32_t payload_header_length;
    uint32_t payload_offset;
};

struct rofl_payload_header {
    uint64_t game_id;
    uint32_t game_length;
    uint32_t nr_keyframes;
    uint32_t nr_chunks;
    uint32_t end_startup_chunk_id; // guessed
    uint32_t start_game_chunk_id; // guessed
    uint32_t keyframe_interval; // =60000 guessed
    uint16_t encryption_key_length; // 0x20
};

struct rofl_payload_entry {
    uint32_t id;
    uint8_t type; // 1 for chunk, 2 for keyframe
    uint32_t length;
    uint32_t next_chunk_id; // 0 if is a chunk
    uint32_t offset; // base is start of payload
};

/*
ROFL := rofl_header json rofl_payload_header encryption_key chunk_entries keyframe_entries payload
json := uint8_t*rofl_header.metadata_length
encryption_key := uint8_t*rofl_payload_header.encryption_key_length
chunk_entries := rofl_payload_entry*rofl_payload_header.nr_chunks
keyframe_entries := rofl_payload_entry*rofl_payload_header.nr_keyframes
payload := uint8_t...
*/

// About Signature
/*
Signed SHA1 hash starting from rofl_header.header_length to the end of file,
and can be verified by using the following RSA2048 public key (extracted
from the executable):
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1mV8+Ez6EEdQtCYPewmO
dhG4ElhApH3AQe1TReKZNHP/uYTQSNE9vAly7W/sXFAJPTUtwXqOeFwMqumzuk3T
iXJhQul/zywcBKRawVxgN7qMAdPv7t5AijWh1brDrevdOlwzPwUp24ar96YKDefS
73EFnY1xoEqSs1DnkrwKN0Nb8Sjwgs5XrZiLV03U1SlqJD2nHhhLpAAgnKeY6vJN
/+H3l/TXfvrbi4b+9GjJkGiahREEvJN2FnKSPofI+gPfA2rXUQTNeSDMYsPhAaV6
JPY4iZBpb1//6/p2fTbL1inYDhC5KDuSPPoBHmZFm8gT10jAk1V9fuWeweYAIIve
5wIDAQAB
-----END PUBLIC KEY-----
*/
