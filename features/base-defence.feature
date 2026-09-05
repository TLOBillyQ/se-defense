# language: zh-CN
# mutation-stamp: sha256=2c792104a5215df4e496d8152e80f8d2db30bd321690c6f5552d5f8dd4b77eee
# acceptance-mutation-manifest-begin
# {
#   "background_hash": "c4f507e4bad95d88c201ef86458b8fd1dec20282f34eb290f96b2e72a6161f5b",
#   "feature_name": "Base Defence 无头对局流程",
#   "feature_path": "features/base-defence.feature",
#   "implementation_hash": "sha256:49eaf878ee62d03c2aa5a28b43a464e04d2dd525d52dd1281abb053e1cc0b5ec",
#   "scenarios": [
#     {
#       "index": 0,
#       "mutation_count": 0,
#       "name": "开局前拒绝放置直到自动开始",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "6fdfed9e76cca01d63cb45a7a611d5dd3fef494aa6a46ec830c123ad43752107",
#       "tested_at": "2026-09-05T13:13:34Z"
#     },
#     {
#       "index": 1,
#       "mutation_count": 10,
#       "name": "放置建筑扣除其价格",
#       "result": {
#         "Errors": 0,
#         "Killed": 10,
#         "Survived": 0,
#         "Total": 10
#       },
#       "scenario_hash": "124ce31daffd38cde6ceab2e25cd3eb5ebc3d7b312c31cd05a65f90730414335",
#       "tested_at": "2026-09-05T13:13:36Z"
#     },
#     {
#       "index": 2,
#       "mutation_count": 0,
#       "name": "relay把电网扩展到核心之外",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "55f83b7c69390e3bb9660a6c8e69c9079a1c0fa9803379ff18049c89fc0d0543",
#       "tested_at": "2026-09-05T13:13:36Z"
#     },
#     {
#       "index": 3,
#       "mutation_count": 0,
#       "name": "采空全部资源达成胜利且重开重建对局",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "09adee054ff5d493ccfc468031e13c6ef527135c2040b3a966c5abc0f1c582b4",
#       "tested_at": "2026-09-05T13:13:36Z"
#     },
#     {
#       "index": 4,
#       "mutation_count": 0,
#       "name": "核心被摧毁达成游戏结束",
#       "result": {
#         "Errors": 0,
#         "Killed": 0,
#         "Survived": 0,
#         "Total": 0
#       },
#       "scenario_hash": "d3d2b9e1dd35525ba5d9c15d0035dc711ce172c2ea38e3b0176da42d4de43a5e",
#       "tested_at": "2026-09-05T13:13:36Z"
#     }
#   ],
#   "tested_at": "2026-09-05T13:13:36Z",
#   "version": 1
# }
# acceptance-mutation-manifest-end
功能: Base Defence 无头对局流程

背景:
  假如 一局全新的无头游戏
  并且 客户端已就绪

场景: 开局前拒绝放置直到自动开始
  假如 游戏处于Pregame模式
  当 客户端发送放置意图turret
  那么 没有建筑处于放置中
  当 游戏推进100个tick
  那么 游戏处于Playing模式
  并且 金钱为100

场景大纲: 放置建筑扣除其价格
  当 游戏推进100个tick
  那么 游戏处于Playing模式
  当 客户端发送放置意图<建筑>
  并且 客户端点击棋盘<x> <z>
  并且 游戏推进4个tick
  那么 棋盘上<建筑>的数量为<数量>
  并且 金钱减少了<价格>

例子:
  | 建筑   | x | z | 数量 | 价格 |
  | turret | 3 | 0 | 1    | 100  |
  | relay  | 0 | 3 | 1    | 50   |

场景: relay把电网扩展到核心之外
  当 游戏推进100个tick
  那么 游戏处于Playing模式
  当 GM把金钱设为1000
  并且 客户端发送放置意图relay
  并且 客户端点击棋盘0 3
  并且 游戏推进10个tick
  那么 棋盘上relay的数量为1
  并且 relay已通电
  当 客户端发送放置意图radar
  并且 客户端点击棋盘0 6
  并且 游戏推进10个tick
  那么 棋盘上radar的数量为1
  并且 radar已通电

场景: 采空全部资源达成胜利且重开重建对局
  当 游戏推进100个tick
  那么 游戏处于Playing模式
  当 GM采空全部资源
  并且 游戏推进3个tick
  那么 游戏处于Victory模式
  并且 victory横幅可见
  当 客户端重开对局
  并且 游戏推进1个tick
  那么 游戏处于Pregame模式
  并且 棋盘上实体总数为7

场景: 核心被摧毁达成游戏结束
  当 游戏推进100个tick
  那么 游戏处于Playing模式
  当 GM摧毁核心
  并且 游戏推进3个tick
  那么 游戏处于GameOver模式
  并且 gameover横幅可见
