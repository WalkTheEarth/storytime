# Novel Apps — API Reference

Reverse-engineered API documentation for the four services analyzed in `work/`.
All flows were verified live against production unless marked otherwise.
Test story codes (`TEST STORY CODES ALL APPS.txt`):

| App | Package | Base URL | Story code | Status |
|---|---|---|---|---|
| MotoNovel | `com.motonovel.reader` | `https://motonovel-api.bkneng.com` | `599002` | verified end-to-end |
| GoodNovel | — | `https://www.goodnovel.com` | `R67281` | verified end-to-end (web API, no sign needed) |
| Novel Master | `com.master.novel` | `https://api.novel-master.com` | `538822` | reads verified; writes need app-injected common params |
| PlotNovel | — | `https://server.read.plotread.com/plot-novel` | `684996` | verified end-to-end (no sign needed) |

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

`POST /hwyc/book/searchSuggest` body `{"query":"R67281","limit":5}`:

```
{code:0, data:[{categoryID:36, contentID:"R67281", name:"The Alpha King's Rejected Mate", …}]}
```

Story codes resolve through plain `query` search. `POST /hwyc/book/search`
returns 404 — only `searchSuggest` exists.

### 2.2 Book detail

`POST /hwyc/book/detail` body `{"contentID":"R67281"}` → `bookId` (e.g.
`8438145034220524`), `vipFlag` (2 = has paid chapters), `tagNames`, prices,
`chapterCount` (~7134 free), etc.

### 2.3 Chapter list

`POST /hwyc/chapter/list` body `{"bookId":<bookId>,"offset":0,"limit":1000}` →
`data[]` = chapter ids. Note: `data` is a **list** here, not a map.
Chapter ids are sequential for a book (each next chapter −1 in id order as
returned; verify via detail).

### 2.4 Chapter content

`POST /hwyc/chapter/detail` body `{"chapterId":<id>}` → `isVip`, `isSample`,
`price`, `nextChapterId`, content fields. `/hwyc/chapter/content` and
`/hwyc/home/index` return 404 on the web host.

---

## 3. Novel Master (`com.master.novel` → `api.novel-master.com`)

Base: `https://api.novel-master.com` (non-prod hosts exist:
`api-test.`, `api-uat.`, `api-fat.`, `api-pre.` — same paths). JSON POST/GET,
headers: `Content-Type: application/json; charset=utf-8`,
`Accept: application/json`, `User-Agent: okhttp/4.8.0`.
Responses: `{code:0, msg:"success", data:…}` (`code!=0` = error; account
endpoints use `message` + `success:true` and code `050000` = bad nonce).

Pagination: `page` (1-based), `size`.

### 3.1 Sign (headers only)

`x-sign`, `x-timestamp`, `x-nonce` — **headers only, never query params**.
Sign covers URI path + timestamp + nonce + `MD5(body)`. The nonce comes from
`/account/nonce` and is reusable across many calls. Read endpoints below work
without any sign; sign is required for account/write operations.

### 3.2 Nonce + token

- `POST /account/nonce` body `{"nonceType":1}` → `data` = nonce string (hex uuid).
- `GET /account/tokens` (nonce header) → `data` = JWT bearer token for
  `/account/*` calls.

### 3.3 Search (story code works as plain query)

`POST /novel/search` body `{"page":1,"size":20,"search":"538822"}` →
`data.list[]`:

```
id:68714, novel_code:"538822", title, author_name, novel_cover,
chapter_count:177, first_chapter_id:6142472, last_chapter_id:6142648,
is_finished:false, source:2, tags, vip flags
```

### 3.4 Chapter detail (content)

`POST /novel/chapter` body `{"id":<chapter_id>}` →

```
{chapter_id, novel_id, paragraph:"<content>", is_free, is_vip,
 prev_chapter_id, next_chapter_id}
```

Paging: `{"id":<id>,"next":1}` → next chapter (works; `novel_id` param is
rejected with 500). Note `paragraph` is HTML with `<p>` separators.

### 3.5 Other verified read endpoints

- `GET /novel/hot/list?limit=10` → hot novels (same list shape as search).
- `GET /novel/category` → `[{categoryId:33,name:"Romance"}, …]` (12 categories:
  Romance 33, Werewolf 102, Mafia 103, Billionaire 104, Fantasy 105,
  Science Fiction 106, Teen Fiction 107, LGBTQ 108, Horror 109, New Adult 110,
  Short Story 111, Young Adult 112).
- `POST /novel/category/novel` body `{"categoryId":33,"page":1,"size":20}` → list.
- `POST /novel/tag/novel` body `{"tagId":42,"page":1,"size":20}` → list.
- `GET /novel/home/section/list?page=0&size=10` → home sections
  (`HomeSectionData`: novel + rank arrays).

### 3.6 Endpoints that exist but need app-injected params

- `POST /novel/detail` `{"id":…}` → **500** (requires guest registration context).
- `POST /account/register_guest` → **500** (needs common params injected by the
  app's request wrapper — not reproduced).
- `POST /account/guest/login` → 500; `/account/novel/read/record` and
  `/account/novel/read/tag` → **401** (need the JWT from `/account/tokens`).
- `POST /novel/bookshelf` `{"novelId":…}` → **404** (not deployed at this path).

---

## 4. PlotNovel (`server.read.plotread.com/plot-novel`)

Base: `https://server.read.plotread.com/plot-novel`. No sign, no login needed
for content. Common query params on every call: `platform=1`, `appType=1`,
`deviceType=2`. Responses: `{code:0, msg, data}`.

### 4.1 Search (story code works as bookName)

`POST /search?bookName=684996&pageSize=20&pageNum=1&platform=1&appType=1&deviceType=2`
(JSON body with the same fields also accepted) →

```
data.list:[{bookId:56817, bookName:"Alpha's Secret Luna", authorName, coverUrl,
            category Name, total words/chapters, …}], total:1
```

### 4.2 Chapter list

`POST /chapter/queryChapter?bookId=56817&pageNum=1&pageSize=20&platform=1&appType=1&deviceType=2`
→ `data.list[]` of `{chapterId, chapterTitle, isVip, price, …}`, `total` (e.g.
144). Paginated.

### 4.3 Chapter content

`POST /chapter/content?chapterId=1164553&bookId=56817&platform=1&appType=1&deviceType=2`
→ `data.chapterText` (full text, `\n` separated).

### 4.4 Full list with inline content

`POST /chapter/getChapterList?bookId=56817&pageNum=1&pageSize=1000&platform=1&appType=1&deviceType=2`
→ complete chapter list **including chapterText** for each chapter — one call
for the whole book.

### 4.5 Home feeds

```
POST /home/getHomeBanner?positionId=2&platform=1&appType=1&deviceType=2
POST /home/getDailyRecommend?pageNum=1&pageSize=6&platform=1&appType=1&deviceType=2
POST /home/getGuessYouLike?pageNum=1&pageSize=6&platform=1&appType=1&deviceType=2
```

### 4.6 Login-gated (needs session; not required for reading)

`POST /user/bookshelf/list?pageNum=1&pageSize=10&platform=1&appType=1&deviceType=2`
and other `/user/*` routes.

---

## Appendix: client mapping

`client/lib/sources/` implements the four adapters against these APIs:

| Adapter | Flow used |
|---|---|
| `moto_novel.dart` | guest login (RSA public-op + AES-CBC in Dart) → signed `indexV2` → `catalogues` → `h5/chapter` |
| `good_novel.dart` | `searchSuggest` → `book/detail` → `chapter/list` → `chapter/detail` |
| `novel_master.dart` | `search` → `chapter` (`{"id":…}`), `next:1` paging |
| `plot_novel.dart` | `search` → `queryChapter` → `content` (or `getChapterList`) |

Story-code import (`client/lib/core/registry.dart`) tries each source's plain
search with the code, since all four services resolve story codes via search.
