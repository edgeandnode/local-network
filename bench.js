//

"use strict";

import { check } from 'k6';
import http from "k6/http";

const max_connections = 500;

export const options = {
  stages: [{ duration: '20s', target: max_connections }],
  summaryTrendStats: ['med', 'p(99)', 'max'],
};

// curl "http://localhost:7602/subgraphs/id/QmfVaeTxHGQVtEc9hKPMdtvQeaFYPUSfGWr8HXU8rSsB49" \
//   -H 'content-type: application/json' -H "authorization: bearer deadbeefdeadbeefdeadbeefdeadbeef" \
//   -d '{"query": "{ _meta { block { number } } }"}'
// {"message":"No valid receipt or free query auth token provided"}%

export default function() {
    let response = http.post(
        'http://localhost:7602/subgraphs/id/QmfVaeTxHGQVtEc9hKPMdtvQeaFYPUSfGWr8HXU8rSsB49',
        '{"query": "{ _meta { block { number } } }"}',
        { headers: {
          'content-type': 'application/json',
          'tap-receipt': "{\"message\":{\"allocation_id\":\"0xb197eba8a4698db3ce6997645d703ba12819a4e9\",\"timestamp_ns\":1722995212047356771,\"nonce\":5464876947611066258,\"value\":40000000000000},\"signature\":{\"r\":\"0xca2e3a7d46f428cb9a4ca65eaf3b9c17de69abe008a370a47d7118e6778f29c2\",\"s\":\"0x732aec85a78cd952c7001d6e6b8249603a5bba888352c8600c4d780edafc8e69\",\"v\":27}}",
        } },
    );
    check(response, {
        'ok': (r) => r.status === 200,
        'success': (r) => {
          const success = r.body.includes('graphQLResponse');
          if (!success) console.log(r.status, r.body);
          return success
        },
    });
};
