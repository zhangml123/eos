#include <eoslib/eos.hpp>
#include <eoslib/db.hpp>

/* @abi simpledb action insert1
 * @abi simpledb table
*/
struct PACKED(record1) {
   uint64_t key;
};

/* @abi simpledb action insert2
 * @abi simpledb table
*/
struct PACKED(record2) {
   uint128_t key1;
   uint128_t key2;
};

/* @abi simpledb action insert3
 * @abi simpledb table
*/
struct PACKED(record3) {
   uint64_t key1;
   uint64_t key2;
   uint64_t key3;
};
