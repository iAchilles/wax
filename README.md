# Wax

WebAuthn library for elixir

<img src="doc/wax.png" width="128"/>

Goal: implement a *comprehensive* FIDO2 library on the server side
(*Relying party* or RP in the WebAuthn terminology) to authenticate users with WebAuthn.

For semantics (FIDO2, WebAuthn, FIDO...), read
[this article](https://medium.com/@herrjemand/introduction-to-webauthn-api-5fd1fb46c285)

## Demo app

You can try out and study WebAuthn authentication with Wax thanks to the
[wax_demo](https://github.com/tanguilp/wax_demo) test application.

See alos a video demonstration of an authentication flow which allows replacing the password
authentication scheme by a WebAuthn password-less authentication:

[![Demo screenshot](https://raw.githubusercontent.com/tanguilp/wax_demo/master/assets/static/images/demo_screenshot.png)](https://vimeo.com/358361625)

## Project status

- Support the FIDO2 standard (especially all types of attestation statement formats and
all mandatory algorithms). See the "Support of FIDO2" section for further information
- This library has **not** be reviewed by independent security / FIDO2 specialists - use
it at your own risks or blindly trust its author!
- This library does not come with a javascript library to handle WebAuthn calls
- At the time of publishing version 0.1.0, there is no comprehensive test suite available
(tests do exist, however, but this may not be sufficient). If you spot a bug, fill an
issue with the output of the javascript WebAuthn call and that'll be fixed as fast as
possible

## Compatibility

OTP21+

## Installation

Add the following line to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wax, github: "tanguilp/wax", tag: "0.1.3"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)

## Usage

To use FIDO2 for authentication, you must first *register* a new FIDO2 key for a user. The
process is therefore the following:
1. Register a FIDO2 key for a user
2. Authenticate as much as you want the user using the FIDO2 key registered in step 1

Optionaly, you might want to store more than one key, for instance if the user have
several authenticators.

The Wax library doesn't provide with a user data store to store the key generated in step
1 and to retrieve it in step 2. Instead, it lets you use any data store. The data to
be stored is described in the `Wax` module's documentation.

### Registration

Wax provides with 2 functions for registration:
1. `Wax.new_registration_challenge/1`: generates a challenge that must subsequently be sent
to the client for use by the javascript WebAuthn API
2. `Wax.register/3`: takes into parameter the response of the WebAuthen javascript API and
the challenge generated in step 1, and verifies it

Since the challenge generated in step 1 must be passed as a paramteter in step 2, it is
required to persist it on the server side, for instance in the session:

```elixir
# generating a challenge

challenge = Wax.new_registration_challenge(login, [])

conn
|> put_session(:challenge, challenge)
|> render(register_key_page, challenge: challenge.bytes)
# the challenge is to be sent on the client one way or another
# this can be direct within the HTML, or using an API call
```

to be then retrieved when verifying the assertion:

```elixir
challenge = get_session(conn, :challenge)

case Wax.register(attestation_object, client_data_json, challenge) do
	{:ok, {key, _}} ->
		# success case

	{:error, _} ->
		# verification failure
end
```

In the success case, a server will save the credential id (generated by the WebAuthn
javascript call) and the cose key in its user database for use for authentication.

The key is a map that looks like:

```elixir
%{
  -3 => <<182, 81, 183, 218, 92, 107, 106, 120, 60, 51, 75, 104, 141, 130,
    119, 232, 34, 245, 84, 203, 246, 165, 148, 179, 169, 31, 205, 126, 241,
    188, 241, 176>>,
  -2 => <<89, 29, 193, 225, 4, 234, 101, 162, 32, 6, 15, 14, 130, 179, 223,
    207, 53, 2, 134, 184, 178, 127, 51, 145, 57, 180, 104, 242, 138, 96, 27,
    221>>,
  -1 => 1,
  1 => 2,
  3 => -7
}
```

It probably doesn't need to be searchable or indexed, which is why one can store as a binary.
To convert back and forth Elixir data structures to binary and store the keys in a database
(SQL, for instance), take a look at the Erlang functions `term_to_binary/1` and
`binary_to_term`.

For further information, refer to the `Wax` module documentation.

### Authentication

The process is quite similar, with 2 functions for authentication:
1. `Wax.new_authentication_challenge/2`: generates a challenge from a list of
(credential id, key) saved during the registration processes. It also has to be sent to
the client for use by the javascript WebAuthn API
2. `Wax.authenticate/5`: to be called to verify the WebAuthn javascript API response
with the returned data (composed of signature, authenticator data, etc.) with the
challenge generated in step 1

This also requires storing the challenge:
```elixir
cred_ids_and_keys = UserStore.get_keys(username)

challenge = Wax.new_authentication_challenge(cred_ids_and_keys, [])

conn
|> put_session(:authentication_challenge, challenge)
|> render(auth_verify_page, challenge: challenge.bytes, creds: cred_ids_and_keys)
# the challenge is to be sent on the client one way or another
# this can be direct within the HTML, or using an API call
```

to be passed as a paramter to the `Wax.authenticate/5` function:

```elixir
challenge = get_session(conn, :authentication_challenge)

case Wax.authenticate(raw_id, authenticator_data, sig, client_data_json, challenge) do
	{:ok, _} ->
		# ok, user authenticated

	{:error, _} ->
		# invalid WebAuthn response
end
```

For further information, refer to the `Wax` module documentation.

## Options
The options are set when generating the challenge (for both registration and
authentication). Options can be configured either globally in the configuration
file or when generating the challenge. Some also have default values.

Option values set during challenge generation take precedence over globally configured
options, which takes precedence over default values.

These options are:

|  Option       |  Type         |  Applies to       |  Default value                | Notes |
|:-------------:|:-------------:|-------------------|:-----------------------------:|-------|
|`origin`|`String.t()`|<ul style="margin:0"><li>registration</li><li>authentication</li></ul>| | Mandatory. Example: `https://www.example.com` |
|`rp_id`|`String.t()` or `:auto`|<ul style="margin:0"><li>registration</li><li>authentication</li></ul>|If set to `:auto`, automatically determined from the `origin` (set to the host) | With `:auto`, it defaults to the full host (e.g.: `www.example.com`). This option allow you to set the `rp_id` to another valid value (e.g.: `example.com`) |
|`user_verified_required`|`boolean()`|<ul style="margin:0"><li>registration</li><li>authentication</li></ul>| `false`| |
|`trusted_attestation_types`|`[Wax.Attestation.type()]`|<ul style="margin:0"><li>registration</li></ul>|`[:none, :basic, :uncertain, :attca, :self]`| |
|`verify_trust_root`|`boolean()`|<ul style="margin:0"><li>registration</li></ul>|`true`| Only for `u2f` and `packed` attestation. `tpm` attestation format is always checked against metadata |

## FIDO2 Metadata service (MDS) configuration

The FIDO Alliance provides with a list of metadata statements of certified **FIDO2**
authenticators. A metadata statement contains trust anchors (root certificates) to verify
attestations. Wax can automatically keep this metadata up to date but needs a access token which
is provided by the FIDO Alliance. One can request it here:
[https://mds2.fidoalliance.org/tokens/](https://mds2.fidoalliance.org/tokens/).

Once the token has been granted, it has to be added in the configuration file (consider
adding it to your `*.secret.exs` files) with the `:metadata_access_token` key. The update
frquency can be configured with the `:metadata_update_interval` key (in seconds, defaults
to 12 hours). Example:

`config/dev.exs`:
```elixir
use Mix.Config

config :wax,
  metadata_update_interval: 3600,
```

`config/dev.secret.exs`:
```elixir
use Mix.Config

config :wax,
  metadata_access_token: "d4904acd10a36f62d7a7d33e4c9a86628a2b0eea0c3b1a6c"
```

Note that some **FIDO1** certififed authenticators, such as Yubikeys, won't be present in this
list and Wax doesn't load data from the former ("FIDO1") metadata Web Service. The FIDO
Alliance plans to provides with a web service having both FIDO1 and FIDO2, but there is no
roadmap as of September 2019.

## Security considerations

- Make sure to understand the implications of not using attested credentials before
accepting `none` or `self` attestation types, or disabling it for `packed` and `u2f`
formats by disabling it with the `verify_trust_root` option
- The FIDO MDS TOC signature is not verified (therefore its integrity relies on
HTTPS and the CDNs serving it)
- This library has **not** be reviewed by independent security / FIDO2 specialists - use
it at your own risks or blindly trust its author! If you're knowledgeable about
FIDO2 and willing to help reviewing it, please contact the author

## Support of FIDO2

[2. Registration and Attestations](https://fidoalliance.org/specs/fido-v2.0-rd-20180702/fido-server-v2.0-rd-20180702.html#registration-and-attestation)
- [x] **Mandatory**: registration support
- [x] **Mandatory**: random challenge
- [2.1. Validating Attestation](https://fidoalliance.org/specs/fido-v2.0-rd-20180702/fido-server-v2.0-rd-20180702.html#validating-attestation)
  - [x] **Mandatory**: attestation validation
  - [x] **Mandatory**: attestation certificate chains (note: can be disabled through an option)
  - [x] **Mandatory**: validation of attestation through the FIDO Metadata Service 
- [2.2. Attestation Types](https://fidoalliance.org/specs/fido-v2.0-rd-20180702/fido-server-v2.0-rd-20180702.html#attestation-types)
  - [x] **Mandatory**: basic attestation
  - [x] **Mandatory**: self attestation
  - [x] **Mandatory**: private CA attestation
  - [ ] *Optional*: elliptic curve direct anonymous attestation
- [2.3. Attestation Formats](https://fidoalliance.org/specs/fido-v2.0-rd-20180702/fido-server-v2.0-rd-20180702.html#attestation-formats)
  - [x] **Mandatory**: packed attestation
  - [x] **Mandatory**: TPM attestation
  - [x] *Optional*: Android key attestation
  - [x] **Mandatory**: U2F attestation
  - [x] **Mandatory**: Android Safetynet attestation

[3. Authentication and Assertions](https://fidoalliance.org/specs/fido-v2.0-rd-20180702/fido-server-v2.0-rd-20180702.html#authn-and-assertion)
  - [x] **Mandatory**: authentication
  - [x] **Mandatory**: random challenge
  - [x] **Mandatory**: assertion signature validation
  - [x] **Mandatory**: TUP verification (note: and also user verified, through an option)

[4. Communication Channel Requirements](https://fidoalliance.org/specs/fido-v2.0-rd-20180702/fido-server-v2.0-rd-20180702.html#communication-channel-requirements)
  - [ ] *Optional*: TokenBinding support

[5. Extensions](https://fidoalliance.org/specs/fido-v2.0-rd-20180702/fido-server-v2.0-rd-20180702.html#extensions)
  - [x] **Mandatory**: registration and authentication support without extension
  - [ ] *Optional*: extension support
  - [ ] *Optional*: appid extension support

[6. Other](https://fidoalliance.org/specs/fido-v2.0-rd-20180702/fido-server-v2.0-rd-20180702.html#other)
  - [x] **Mandatory**: RS1 (RSASSA-PKCS1-v1_5 w/ SHA-1) algorithm support
  - [x] **Mandatory**: RS256 (RSASSA-PKCS1-v1_5 w/ SHA-256) algorithm support
  - [x] *Optional*: RS384 (RSASSA-PKCS1-v1_5 w/ SHA-384) algorithm support
  - [x] *Optional*: RS512 (RSASSA-PKCS1-v1_5 w/ SHA-512) algorithm support
  - [ ] *Optional*: PS256 (RSASSA-PSS w/ SHA-256) algorithm support
  - [ ] *Optional*: PS384 (RSASSA-PSS w/ SHA-384) algorithm support
  - [ ] *Optional*: PS512 (RSASSA-PSS w/ SHA-512) algorithm support
  - [x] **Mandatory**: ES256 (ECDSA using P-256 and SHA-256) algorithm support
  - [x] *Optional*: ES384 (ECDSA using P-384 and SHA-384) algorithm support
  - [x] *Optional*: ES512 (ECDSA using P-521 and SHA-512) algorithm support
  - [ ] *Optional*: EdDSA algorithm support
  - [ ] *Optional*: ES256K (ECDSA using P-256K and SHA-256) algorithm support
  - [ ] **Mandatory**: compliance with the FIDO privacy principles (note: out-of-scope, to be implemented by the server using the Wax library)

[7. Transport Binding Profile](https://fidoalliance.org/specs/fido-v2.0-rd-20180702/fido-server-v2.0-rd-20180702.html#transport-binding-profile)
  - [ ] *optional*: API implementation
