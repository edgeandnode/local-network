import autocannon from 'autocannon'

const duration = 120
const body = '{"query": "{ _meta { block { number } } }"}'
const label = process.argv[2]
const url = process.argv[3]

const run_benchmark = async (connections: number): Promise<autocannon.Result> => autocannon({
  url,
  method: 'POST',
  headers: {
    'content-type': 'application/json',
  },
  body,
  connections,
  duration,
})

const main = async () => {
  console.log([
    'label',
    'connections',
    'errors',
    'timeouts',
    'latency_min',
    'latency_max',
    'latency_avg',
    'requests_min',
    'requests_max',
    'requests_avg',
    'requests_tot',
  ].join(','))
  for (let connections of [10, 20, 30, 40, 50, 60, 70, 80]) {
    const result = await run_benchmark(connections)
    console.log([
      label,
      result.connections,
      result.errors,
      result.timeouts,
      result.latency.min,
      result.latency.max,
      result.latency.average,
      result.requests.min,
      result.requests.max,
      result.requests.average,
      result.requests.total,
    ].join(','))
    await new Promise(f => setTimeout(f, 2000))
  }
}

main()
