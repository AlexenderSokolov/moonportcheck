# Delivery audit

Status: valid

Valid: true

First failed step: -1

```json
{"format":"moonportcheck-delivery-audit","version":1,"status":"valid","valid":true,"first_failed_step":-1,"diagnostics":[],"final_entries":[{"path":"old","kind":"directory","origin":{"root":"","path":""}},{"path":"old/report","kind":"file","origin":{"root":"target","path":"report"}},{"path":"report","kind":"directory","origin":{"root":"","path":""}},{"path":"report/a","kind":"file","origin":{"root":"one","path":"x"}},{"path":"report/b","kind":"file","origin":{"root":"two","path":"x"}}],"trace":[{"step":0,"kind":"mkdir","from":"","to":"old","origin":{"root":"","path":""}},{"step":1,"kind":"move","from":"report","to":"old/report","origin":{"root":"target","path":"report"}},{"step":2,"kind":"mkdir","from":"","to":"report","origin":{"root":"","path":""}},{"step":3,"kind":"copy","from":"x","to":"report/a","origin":{"root":"one","path":"x"}},{"step":4,"kind":"copy","from":"x","to":"report/b","origin":{"root":"two","path":"x"}}]}
```

