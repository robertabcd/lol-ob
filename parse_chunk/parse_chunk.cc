#include <iostream>
#include <fstream>
#include <stdexcept>
#include <functional>
#include <string>

std::string HexDump(const std::string& bin) {
    const char *tb = "0123456789abcdef";
    std::string s;
    for (size_t i = 1; i <= bin.size(); ++i) {
        uint8_t b = bin[i-1];
        s.push_back(tb[b>>4]);
        s.push_back(tb[b&0xf]);
        if (i % 2 == 0)
            s.push_back(' ');
        if (i == bin.size() && i % 16 > 0) {
            for (size_t j = i; j & 0xf; ++j) {
                s.push_back(' ');
                s.push_back(' ');
                if (j % 2)
                    s.push_back(' ');
            }
            i = (i + 16) & ~0xf;
        }
        if (i % 16 == 0) {
            for (size_t j = i-15; j <= i && j <= bin.size(); ++j)
                s.push_back(isprint(bin[j-1]) ? bin[j-1] : '.');
            s.push_back('\n');
        }
    }
    return s;
}

struct Block {
    uint8_t flags;
    uint8_t channel;
    float timestamp;
    uint16_t type;
    std::string param;
    std::string content;

    Block() { Reset(); }

    void Reset() {
        flags = 0;
        channel = 0;
        timestamp = 0.0f;
        type = 0;
        param.clear();
        content.clear();
    }

    enum {
        FLAG_ONE_BYTE_CONTENT_LENGTH = 1 << 0,
        FLAG_ONE_BYTE_PARAM = 1 << 1,
        FLAG_SAME_TYPE = 1 << 2,
        FLAG_RELATIVE_TIME = 1 << 3
    };

    bool HasFlag(int f) const { return flags & f; }

    void Dump(std::ostream& os) const {
        os << "(Block) Type " << (int)type
            << " Flags " << (int)flags
            << " Channel " << (int)channel
            << " Timestamp " << timestamp
            << " ContentLength " << content.size()
            << std::endl;
        os << HexDump(content);
    }
};

class Parser {
public:
    Parser(std::istream& is)
        : is(is)
        , last(&buffers[0])
        , curr(&buffers[1])
        , is_first(true) { }

    void Parse() {
        while (ParseOne());
    }

    void SetHandler(std::function<void (const Block&)> h) {
        handler = h;
    }

private:
    std::istream& is;
    std::function<void (const Block&)> handler;
    Block buffers[2];
    Block *last, *curr;
    bool is_first;

    bool ParseOne() {
        Block &blk = *curr;

        uint8_t marker;
        if (!is.read(reinterpret_cast<char *>(&marker), sizeof(marker))) {
            return false;
        }
        blk.flags = marker >> 4;
        blk.channel = marker & 0xf;

        blk.timestamp = blk.HasFlag(Block::FLAG_RELATIVE_TIME) ?
            (LastBlock().timestamp + 0.001f * ReadPrimitive<uint8_t>()) :
            ReadPrimitive<float>();

        uint32_t content_length = blk.HasFlag(Block::FLAG_ONE_BYTE_CONTENT_LENGTH) ?
            ReadPrimitive<uint8_t>() :
            ReadPrimitive<uint32_t>();

        blk.type = blk.HasFlag(Block::FLAG_SAME_TYPE) ?
            LastBlock().type :
            ReadPrimitive<uint16_t>();

        blk.param.resize(blk.HasFlag(Block::FLAG_ONE_BYTE_PARAM) ? 1 : 4);
        MustRead(&blk.param[0], blk.param.size());

        blk.content.resize(content_length);
        MustRead(&blk.content[0], blk.content.size());

        handler(blk);

        std::swap(last, curr);
        curr->Reset();
        if (is_first) {
            is_first = false;
        }
        return true;
    }

    void MustRead(void *data, size_t len) {
        is.read(reinterpret_cast<char *>(data), len);
        if (!is) {
            throw std::runtime_error("incomplete");
        }
    }

    template <class T>
    T ReadPrimitive() {
        T val;
        MustRead(&val, sizeof(val));
        return val;
    }

    const Block& LastBlock() const {
        if (is_first) {
            throw std::runtime_error("refer to previous block on first block");
        }
        return *last;
    }
};

void HandleBlock_102(const Block& blk) {
    struct Data {
        uint8_t unknown[8];
        uint32_t summoner_name_len;
        char summoner_name[0];
    };
    const Data* data = reinterpret_cast<const Data*>(blk.content.data());
    std::string summoner_name = data->summoner_name;
    std::cout << summoner_name << std::endl;
}

void HandleBlock(const Block& blk) {
    switch (blk.type) {
        case 102: HandleBlock_102(blk); break;
        default:
            blk.Dump(std::cerr);
    }
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        std::cerr << "Usage:" << argv[0] << " file" << std::endl;
        return 1;
    }

    std::ifstream ifs(argv[1]);
    if (!ifs) {
        std::cerr << "Failed to open: " << argv[1] << std::endl;
        return 1;
    }

    try {
        Parser p(ifs);
        p.SetHandler(HandleBlock);
        p.Parse();
    } catch (std::exception& ex) {
        std::cerr << ex.what() << std::endl;
        return 1;
    }
    return 0;
}
