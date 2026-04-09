# FaceCloak API

API to manage privacy settings on detected faces in images.  

## Routes

All routes return JSON.

- GET `/` : root route shows if the Web API is running
- GET `api/v1/face_records/` : returns all face records
- GET `api/v1/face_records/[ID]` : returns details about a single face record with given ID
- POST `api/v1/face_records/` : creates a new face record
- POST `api/v1/face_records/[ID]/assign` : assigns a face record to an assigned user ID
- POST `api/v1/face_records/[ID]/respond` : updates the selected cloak type for a face record

## Install

Install this API by cloning the relevant branch and installing required gems from `Gemfile.lock`:

```bash
bundle install
```

## Test

Run the test script:

```bash
ruby spec/api_spec.rb
```

## Run

Run this API using:

```bash
puma
```
