# Delivery audit

Status: valid

Valid: true

First failed step: -1

```json
{"format":"moonportcheck-delivery-audit","version":1,"status":"valid","valid":true,"first_failed_step":-1,"diagnostics":[],"final_entries":[{"path":"archive","kind":"directory","origin":{"root":"","path":""}},{"path":"archive/y","kind":"file","origin":{"root":"target","path":"b"}},{"path":"b","kind":"file","origin":{"root":"target","path":"a"}},{"path":"c","kind":"file","origin":{"root":"target","path":"b"}}],"trace":[{"step":0,"kind":"mkdir","from":"","to":"archive","origin":{"root":"","path":""}},{"step":1,"kind":"copy","from":"b","to":"archive/y","origin":{"root":"target","path":"b"}},{"step":2,"kind":"move","from":"b","to":"c","origin":{"root":"target","path":"b"}},{"step":3,"kind":"move","from":"a","to":"b","origin":{"root":"target","path":"a"}}]}
```

