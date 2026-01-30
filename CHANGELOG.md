# Changelog

## [1.1.0](https://github.com/jsmenzies/autocommit/compare/v1.0.0...v1.1.0) (2026-01-30)


### Features

* add Groq LLM provider with OpenAI-compatible API ([8fa13df](https://github.com/jsmenzies/autocommit/commit/8fa13dfb86555e4004503e6e6c0d4f759f0484b8))
* add Groq note in provider selection list ([6ff3ab0](https://github.com/jsmenzies/autocommit/commit/6ff3ab0396a60bccdfbea6c7b476480dc8389520))
* update documentation and UI to include Groq provider ([af158b9](https://github.com/jsmenzies/autocommit/commit/af158b933c846fdf463c0687ad7e0cc8243f0117))


### Bug Fixes

* Add validation for empty LLM responses ([c65b4e9](https://github.com/jsmenzies/autocommit/commit/c65b4e95798b3c12c55c8682ab7ef6da5079f787))
* add validation for empty LLM responses and improve error messages ([400a2fb](https://github.com/jsmenzies/autocommit/commit/400a2fbc7980814d688f3a711f39019400d52d8a))
* **cmd:** simplify commit logic and remove redundant checks ([f3381e6](https://github.com/jsmenzies/autocommit/commit/f3381e6fa684e1b6a3b9d4ea04f93b38187e360b))
* **cmd:** simplify commit logic and remove redundant checks ([366faa9](https://github.com/jsmenzies/autocommit/commit/366faa9a8fc7a4a9e982fb623ce853f1fe5af085))
* **prompt:** change user prompt for commit options ([2adbff0](https://github.com/jsmenzies/autocommit/commit/2adbff013baf03c6d968d13e8053322b91977a9e))
* **prompt:** return default system prompt from GetDefaultSystemPrompt ([ca68f11](https://github.com/jsmenzies/autocommit/commit/ca68f119732c30273f6703ff30ad4af9cc92f6f8))


### Documentation

* Update README with TUI, auto_add, and model features ([b121b45](https://github.com/jsmenzies/autocommit/commit/b121b4550f41498d96ab12c96960beb57e50841b))
* update README with TUI, auto_add, and model selection features ([7f0b395](https://github.com/jsmenzies/autocommit/commit/7f0b395f200a11f87ada5a27f8a80d6bfd0a4383))


### Code Refactoring

* **cmd:** simplify auto-add logic to unconditionally stage all changes ([f2b31bd](https://github.com/jsmenzies/autocommit/commit/f2b31bdc82d3a1e54695eb8d3069458db11d7cf6))
* improve code quality - DRY, modularization, and features ([814ef82](https://github.com/jsmenzies/autocommit/commit/814ef82aee4224ae2a1fecee745b7463f1e4ff1b))

## 1.0.0 (2026-01-30)


### Features

* update TUI model with improved state management ([6483622](https://github.com/jsmenzies/autocommit/commit/6483622f7e711ab7343bf839f389d2cd175816a2))
* update TUI model with improved state management ([3161896](https://github.com/jsmenzies/autocommit/commit/3161896ce06e6680b648c2206aad7c20064fa3f0))


### Bug Fixes

* add missing main.go entry point ([2334397](https://github.com/jsmenzies/autocommit/commit/233439730d1000eb06d16b68b0131a38e93ce876))
* correct .gitignore to not ignore cmd/autocommit directory ([02d81ee](https://github.com/jsmenzies/autocommit/commit/02d81eecc01b1608abfafeb3ff09196f47fb2bbf))


### Documentation

* update README with Homebrew and Scoop installation instructions ([8996602](https://github.com/jsmenzies/autocommit/commit/899660236f3491adb4443da9d3a61072730c1f0f))
