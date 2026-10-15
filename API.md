# Novel Apps — API Reference

Reverse-engineered API documentation for the four services analyzed in `work/`.
All flows were verified live against production unless marked otherwise.
Test story codes (`TEST STORY CODES ALL APPS.txt`):

| App | Package | Base URL | Story code | Status |
|---|---|---|---|---|
| MotoNovel | `com.motonovel.reader` | `https://motonovel-api.bkneng.com` | `599002` | verified end-to-end |
| GoodNovel | — | `https://www.goodnovel.com` | `R67281` | verified end-to-end (web API, no sign needed) |
| Novel Master | `com.master.novel` | `https://api.novel-master.com` | `538822` | long novels readable end-to-end (see §3.1) |
| PlotNovel | — | `https://server.read.plotread.com/plot-novel` | `684996` | verified end-to-end via `/app/*` + tourist login |

> **Catalog note (2026-10-15):** all four services migrated their catalogs.
> Old story codes/ids may be dead (e.g. GoodNovel `R67281` and the earlier
> Novel Master id space). Codes in the table were re-verified after the
> migration. Novel Master's `/novel/detail` and the `code:0` envelope are
> gone; §3 describes the current API.

Test scripts: `work/moto/test_moto_novel.py` (full CLI), `work/moto/moto_flow.py`
(login flow variants). The Flutter client in `client/` implements all four.

---

## 1. MotoNovel (`com.motonovel.reader`)

Base: `https://motonovel-api.bkneng.com/oversea-` (all paths below are appended,
e.g. `.../oversea-user/out/login/guest`). Requests are
`application/x-www-form-urlencoded`. Responses are JSON `{code, msg, data}`;
`code: 0` = success. HTTP `424` = auth not seen by the service (missing/wrong
token placement), `401` = no token, `403` = bad signature.

### 1.1 Guest login — `POST user/out/login/guest`

Form params: `device` (any stable id) + common params:

| param | value |
|---|---|
| `n1` | `1` |
| `n2` | current time in **milliseconds** |
| `n3` | `1` |
| `n4` | `android` |
| `n5` | app version (e.g. `1.4.8`) |
| `n6` | `1` |
| `n7` | `en` |
| `n8` | `US` |

Response: `data.userName` (guest username) and `data.data = {aesKey, aesData}`:

- `aesKey` — base64 blob, one RSA block (128 bytes, e=65537) in **PKCS#1 v1.5
  type-1** form (`00 01 FF…FF 00 <key>`). The server signs the AES key with its
  private key; the client "public-decrypts": `m = raw^e mod n` using the
  **login public key** (`login_public.pem`, extracted from the APK), then takes
  the bytes after the first `0x00` following the header — that is the
  **base64-encoded AES key**.
- `aesData` — AES-128-CBC ciphertext. Key = `b64decode(aesKey_b64)`,
  **IV = key[:16]**. Plaintext (PKCS7-padded) is JSON:
  `{token, userPriKey}` where `userPriKey` is a PKCS#8 DER private key, base64.

### 1.2 Signature (all `opmcapi/*`, `user/*`, `download/*`, `order/*` calls)

Every authenticated request carries: `username`, `device`, `timestamp` (ms),
`token` (from login), the common `n1..n8`, endpoint params, and `sign`.

`sign` = `Base64(SHA1WithRSA(canonical))`, signed with `userPriKey`, where
`canonical` = `k=v&k=v&…` of **only whitelisted params** (from
`AbsNetHelper.Y()`, `sources/s3/f.java`), sorted by key, empty values skipped.
The whitelist includes:

```
username device timestamp token accessToken page size searchStr bookId
chapterId chapterName paragraphId type code title content key keys level
state count days month times origin platform channel channelId channels
topicId talkId productId cardId gearId seriesId interestKeys switchOn
modelType indexType frequencyId input targetName talkIds positionX positionY
externJson versionTag ancestorId parentId address aid autoCommit value
extensionId bid id chapterIds bookIds
```

Non-whitelist params (e.g. `n1..n8`, `os`, `appmode`, `deviceType`) are still
sent but are not part of the signature.

### 1.3 Token placement per service

- `opmcapi/*` — reads `token` from the **form body** (POST).
- `user/*` and `download/*` — read auth from the **query string**; use **GET**
  with all signed params in the query. (`424` with form-only token.)

### 1.4 Story code → book (search)

`POST opmcapi/out/search/indexV2` with `searchStr=<story code>&page=1&size=5`.

Response `data.result[]` entries contain:

```
extensionId   "2107733316980199424"
extensionName "BOOK[1024370]-KOC[24]"   <- bid = number inside BOOK[...]
showName      "My Roommate's Late Night Calls Will Be Broadcast Campus-Wide"
keywords      "599002"
picUrl, wordNum, chapterNum, isFinish, description, classificationLevelOne/Two
```

The **bid** (book id) is parsed from `extensionName` via `BOOK\[(\d+)\]`.

Note: `opmcapi/out/search/extensionBind` (`extensionId` param) exists in the
app but requires a fully authenticated (non-guest) session — returns
`424 "token 过期"` for guests. Search is the working story-code path.

### 1.5 Chapter catalogue

`POST opmcapi/out/book/catalogues` with `bookId=<bid>` (signed form POST).

```
data: {isFinish:1, feePoint:2, maxChapterId:2, minChapterId:1, feeUnit:1,
       contents:[{chapterId, chapterName, wordNum, chapterType, feeType, volumeNo}]}
```

`feeType`: `2` = free, `1` = paid.

### 1.6 Chapter content

`GET download/out/h5/chapter?bookId=<bid>&chapterId=<cid>&<signed params>`
(signed params incl. `token` in the query string).

```
data: {chapterName:"Chapter 1", content:"<full text with \n>"}
```

### 1.7 Other discovered routes (from `sources/u1/f.java`, not all tested)

```
user/out/login/oauthLogin              user/out/email/login/password
user/out/info/accountDestroy           user/out/info/mix
user/out/info/avatar/upload            user/out/info/user/update
user/out/info/queryVoucher              user/out/info/report
user/out/recharge/orderCreateV2        user/out/recharge/vipOrderCreate
user/out/recharge/getOrder             user/out/recharge/getOrdersByUsername
user/out/recharge/getBookOrderByUsername
user/out/recharge/getVipByUsername     user/out/google/pay   user/out/google/renewPay
user/out/welfare/checkInData           user/out/welfare/queryCheckInDataAndTaskData
user/out/tf/report
opmcapi/out/search/config              opmcapi/out/search/indexV2
opmcapi/out/search/extensionBind       opmcapi/out/frequency/listV2
opmcapi/out/frequency/detail           opmcapi/out/frequency/board
opmcapi/out/frequency/vip/getVipProduct
opmcapi/out/frequency/board/activity/userGift/bookList
opmcapi/out/book/board/list            opmcapi/out/book/maxChapterId
opmcapi/out/book/catalogues            opmcapi/out/book/front
opmcapi/out/book/bookCover             opmcapi/out/book/end
opmcapi/out/book/audio/play            opmcapi/out/scheme/gear/listAll
opmcapi/out/help/text
download/out/chapters/drm              download/out/chapters/enc/download
download/out/chapters/asset/download   download/out/bookMark/query|save|delete
download/out/bookBase/get|save         download/out/enc/timestamp
download/out/book/collect              download/out/bookshelf/books/show
download/out/shelf/upload|download     download/out/h5/chapter
order/out/chapter/orderCreate|submit   order/out/chapters/batch/orderCreate|submit
order/out/book/orderCreate             order/out/qs/book/submit
asset/out/list                         asset/out/chapters/list
asset/out/chapters/check
```

---

## 2. GoodNovel (`www.goodnovel.com`)

No signature required for the endpoints below. Requests are JSON POST to
`https://www.goodnovel.com` paths. Responses: `{code:0, data:…}`.

The app's native host is `api-akm.goodnovel.com`; a sign (key `b70449c`) is
only needed on `/hwyc/account/signInAnonymously`, which we don't need — all
content endpoints work unauthenticated on the web host.

### 2.1 Story code → book

Two search endpoints exist:

- `POST /hwyc/book/search` body `{"keyword":"…","current":1,"size":15}` →
  `data.records[]` with `bookId`, `bookName`, `pseudonym`, `cover`,
  `introduction`, `chapterCount`. **This is the one the client uses.**
- `POST /hwyc/book/searchSuggest` body `{"query":"…","limit":5}` →
  `data[]` with `contentID` (string code). Worked before the catalog
  migration; may return non-`data` responses for dead codes now.

Story codes resolve through plain keyword search on either endpoint.

### 2.2 Book detail

`POST /hwyc/book/detail` body `{"contentID":"R67281"}` → `bookId` (e.g.
`8438145034220524`), `vipFlag` (2 = has paid chapters), `tagNames`, prices,
`chapterCount` (~7134 free), etc.

### 2.3 Chapter list (complete, single call)

`POST /hwyc/chapter/list` body `{"bookId":<bookId>,"current":1,"size":10000}`
→ `data[]` = **volumes**, each `{chapters:[{id, chapterName, unlock, type,
charge, seoChapterName, …}]}`.

**Paging is ignored** — one call returns the complete list (verified with a
246-chapter book: page 1 == page 2). Do not loop; you'll get duplicates.

### 2.4 Chapter content

`POST /hwyc/chapter/detail` body `{"chapterId":<id>}` → `isVip`, `isSample`,
`price`, `nextChapterId`, content fields. `/hwyc/chapter/content` and
`/hwyc/home/index` return 404 on the web host.

---

## 3. Novel Master (`com.master.novel` → `api.novel-master.com`)

Base: `https://api.novel-master.com`. **Current API (verified 2026-10-15)**
— JSON POST only, envelope `{ret, msg, data}` with `ret: 1` = OK:

```
POST /novel/search  {q, offset}      -> {ret:1, data:{list:[…]}}
POST /novel/chapter {id: chapterId}  -> {ret:1, data:{novel, chapter, is_vip}}
```

The older `code:0`/`data` envelope (`{page,size,search}` search, `next:1`
chapter paging, ids like `68714`/`6142472`) is **gone** — those routes now
return `-102 Request parameter error`.

### 3.1 Error codes

| ret | msg | meaning |
|---|---|---|
| 1 | OK | success |
| -102 / -103 | Request parameter error / Failed to parse parameters | wrong body shape |
| -4001 | 小说不存在 | novel not found |
| -4002 | 章节不存在 | chapter/content not found |

`msg` is often Chinese; match on `ret`. HTTP may return a bare `null` body
(e.g. dead `/novel/detail`).

### 3.2 Search

`POST /novel/search` body `{"q":"<keyword or story code>","offset":0}` →
`data.list[]`:

```
id, title, content (600-char teaser), type:"vip", likes, member{name},
cover{url}, imgs, tags[{id,name}], ct, is_long_story, is_ongoing,
is_adult_only, first_chapter_id (long novels only), is_self_book
```

Story codes work as `q`. Page size is fixed at 20; `offset` = (page-1)*20.
Numeric book ids do **not** resolve as `q` — cache search items instead.

### 3.3 Chapter content

`POST /novel/chapter` body `{"id": <chapterId>}` →

```
data.novel    {id, title, first_chapter_id, is_long_story, member, cover, tags, …}
data.chapter  {id, pid (novel id), num, name, paragraphs:[{content}], ut, type,
               is_unlock, price}
data.is_vip
```

Locked chapters return `is_unlock:false` and no usable paragraphs.

### 3.4 Rebuilding the full table of contents

The server **withholds the chapter list from this app version** (the RN app
reads `novel.chapters`, which is never sent — the app itself tells users to
"upgrade to the latest version to view … long novels"). However chapter ids
are allocated in **contiguous per-novel blocks**: chapter 1 has id
`novel.first_chapter_id`, `num = id - first + 1`, and the block ends where
the next id's `pid` differs (or errors -4001 for deleted novels). So:

1. `first = novel.first_chapter_id` (from search)
2. Exponential + binary search for the largest `k` with
   `chapter(first+k).pid == novel.id` (~2·log₂(count) requests)
3. ToC = ids `first..first+k`, titles `Chapter N` (fetch a chapter for its
   real `name` if needed)

Verified: book `1047515664` → block `91213..91221` (9 chapters);
`538822`'s book → block `116977..116988` (12 chapters, ch.6+ VIP).

### 3.5 Short novels are not readable

`is_long_story:false` books have **no readable content** on this API:
`/novel/detail` returns a bare `null` for every id/param variant
(`{pid: <novelId>}` is the only accepted shape — the RN app sends exactly
that). Search `content` is only a 600-char teaser.

### 3.6 Legacy/other endpoints

- `POST /novel/detail {pid: <novelId>}` → `null` (dead).
- `POST /novel/chapter {pid: <novelId>, chapter: N}` → always chapter 1
  (`chapter` is ignored; also 1-paragraph previews).
- Older account/nonce/JWT flows (`/account/nonce`, `/account/tokens`) date
  from the retired `code:0` API and were not re-verified.

---

## 4. PlotNovel (`server.read.plotread.com/plot-novel`)

Base: `https://server.read.plotread.com/plot-novel`. **Current app API**
(verified 2026-10-15) lives under `/app/*` and needs a tourist
session; the older non-`/app` routes still exist but return **401** for
tourist tokens (they require a real user login — not reproduced).

### 4.1 Tourist login

`POST /app/touristLogin` (form, **charset=UTF-8 required**):
`email=<any>&code=123456&deviceId=<any>` → `result.token` (JWT, ~60 min).
Send as `Authorization: <token>` (no Bearer prefix).

### 4.2 Search (story code works as keyword)

`GET /app/novel/searchNovel?keyword=…&pageNo=1&pageSize=20` →
`result.records[]`: `{id, name (Chinese), enName, authorName, coverImage,
introduction, chapterNum, status}`. Story codes resolve via keyword.

### 4.3 Chapter list + content (complete, single call)

`GET /app/chapter/chapterListByNovel?novelId=…&pageNo=1&pageSize=100` →
`result.chapters[]` of `{id, chapterNo, chapterTitle, chapterContent
(inline full text), unlocked, izFree, …}`.

**The list is complete in one response** — `pageNo`/`pageSize` are ignored
(hard window of 20; current catalog books are ≤20 chapters, matching
`chapterNum` from search). One call gives the whole book with inline text.

### 4.4 Other `/app/*` routes (from the Flutter snapshot; not all tested)

```
/app/novel/categories  /app/novel/categoryList  /app/novel/otherPage
/app/novel/page  /app/novel/randomRecommend  /app/novel/topList
/app/chapter/unlockChapter  /app/read/addRecord  /app/read/bookshelfList
/app/read/listRecord  /app/read/delRecords  /app/read/batchOperate
/app/read/operateNovel  /app/user/userInfo  /app/user/bindEmail
/app/user/cancelAccount  /app/login  /app/sendCode
/app/feedback  /app/purchase/google/createOrder  /app/purchase/google/verify
/app/recharge/configList
```

### 4.5 Legacy non-`/app` routes (401 for tourists)

`/chapter/queryChapter`, `/chapter/content`, `/chapter/getChapterList`,
`/search`, `/home/*`, `/user/*` — the pre-migration API. Endpoints answer,
but reject tourist tokens (`401` with Bearer or raw token); they likely
require a real registered account.

---

## Appendix: client mapping

`client/lib/sources/` implements the four adapters against these APIs:

| Adapter | Flow used |
|---|---|
| `moto_novel.dart` | guest login (RSA public-op + AES-CBC in Dart) → signed `indexV2` → `catalogues` (complete list) → `h5/chapter` |
| `good_novel.dart` | `/hwyc/book/search` → `/hwyc/chapter/list` (single complete call) → `chapter/detail` |
| `novel_master.dart` | `{q,offset}` search → contiguous-id-block binary search for the full ToC → `/novel/chapter {id}` per chapter |
| `plot_novel.dart` | tourist login → `searchNovel` → `chapterListByNovel` (complete list with inline text) |

Story-code import (`client/lib/core/registry.dart`) tries each source's plain
search with the code, since all four services resolve story codes via search.
