defmodule Pattern.Dispatcher.NodeTest do
  use ExUnit.Case, async: true

  alias Pattern.Dispatcher.Node
  import Pattern.Code, only: [and_: 2, or_: 2, not_: 1, access_: 1, op_: 2]

  setup do
    %{
      node: %Node{
        subscriptions: MapSet.new(["dummy subscription"]),
        operations: %{
          "dummy operation" => %{
            true: %Node{}
          },
          {:access, [:dummy_key]} => %{
            "dummy operation" => %Node{}
          }
        }
      }
    }
  end

  test "put true", %{node: node} do
    expected = %Node{
      node
      | subscriptions: MapSet.put(node.subscriptions, "subscription")
    }

    assert expected == Node.put(node, true, "subscription")
  end

  test "put operation", %{node: node} do
    actual =
      node
      |> Node.put(op_(:<>, ["a", "b"]), "1")

    expected = %Node{
      node
      | operations:
          Map.merge(
            node.operations,
            %{
              op_(:<>, ["a", "b"]) => %{
                true: %Node{
                  subscriptions: MapSet.new(["1"])
                }
              }
            }
          )
    }

    assert expected == actual
  end

  test "put :==", %{node: node} do
    actual =
      node
      |> Node.put(op_(:==, [access_([:key1, :key2]), "a"]), "1")
      |> Node.put(op_(:==, ["b", access_([:key1, :key2])]), "2")
      |> Node.put(op_(:==, ["a", access_([:key1, :key3])]), "3")
      |> Node.put(op_(:==, [access_([:key1, :key3]), "a"]), "4")

    expected = %Node{
      node
      | operations:
          Map.merge(
            node.operations,
            %{
              {:access, [:key1, :key2]} => %{
                "a" => %Node{
                  subscriptions: MapSet.new(["1"])
                },
                "b" => %Node{
                  subscriptions: MapSet.new(["2"])
                }
              },
              {:access, [:key1, :key3]} => %{
                "a" => %Node{
                  subscriptions: MapSet.new(["3", "4"])
                }
              }
            }
          )
    }

    assert expected == actual
  end

  test "put not operator", %{node: node} do
    actual =
      node
      |> Node.put(access_([:key1]), "1")
      |> Node.put(not_(access_([:key1])), "2")
      |> Node.put(not_(access_([:key2])), "3")

    expected = %Node{
      node
      | operations:
          Map.merge(
            node.operations,
            %{
              {:access, [:key1]} => %{
                true: %Node{
                  subscriptions: MapSet.new(["1"])
                },
                false: %Node{
                  subscriptions: MapSet.new(["2"])
                }
              },
              {:access, [:key2]} => %{
                false: %Node{
                  subscriptions: MapSet.new(["3"])
                }
              }
            }
          )
    }

    assert expected == actual
  end

  test "put and operator", %{node: node} do
    code1 =
      and_(
        "a",
        and_(
          and_("b", "c"),
          "d"
        )
      )

    code2 =
      and_(
        "a",
        and_(
          and_("b", "c"),
          "d"
        )
      )

    actual1 =
      node
      |> Node.put(code1, "1")

    actual2 =
      node
      |> Node.put(code2, "1")

    expected = %Node{
      node
      | operations:
          Map.merge(
            node.operations,
            %{
              "a" => %{
                true: %Node{
                  operations: %{
                    "b" => %{
                      true: %Node{
                        operations: %{
                          "c" => %{
                            true: %Node{
                              operations: %{
                                "d" => %{
                                  true: %Node{
                                    subscriptions: MapSet.new(["1"])
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          )
    }

    assert expected == actual1
    assert expected == actual2
  end

  test "put or operator", %{node: node} do
    code =
      or_(
        "a",
        or_(
          or_("b", "c"),
          "d"
        )
      )

    actual =
      node
      |> Node.put(code, "1")

    expected = %Node{
      node
      | operations:
          Map.merge(
            node.operations,
            %{
              "a" => %{
                true: %Node{
                  subscriptions: MapSet.new(["1"])
                }
              },
              "b" => %{
                true: %Node{
                  subscriptions: MapSet.new(["1"])
                }
              },
              "c" => %{
                true: %Node{
                  subscriptions: MapSet.new(["1"])
                }
              },
              "d" => %{
                true: %Node{
                  subscriptions: MapSet.new(["1"])
                }
              }
            }
          )
    }

    assert expected == actual
  end

  test "delete", %{node: node} do
    expected = %Node{
      node
      | subscriptions: MapSet.put(node.subscriptions, "subscription")
    }

    actual =
      node
      |> Node.put(true, "delete me")
      |> Node.put(true, "subscription")
      |> Node.delete(true, "delete me")

    assert expected == actual
  end

  test "get" do
    node = %Node{
      subscriptions: MapSet.new(["a"]),
      operations: %{
        {:access, [:key1]} => %{
          "b" => %Node{
            subscriptions: MapSet.new(["b"])
          }
        },
        {:access, [:key2]} => %{
          "c" => %Node{
            subscriptions: MapSet.new(["c"])
          }
        }
      }
    }

    assert MapSet.new(["a"]) == Node.get(node, %{key1: "a", key2: "a"})
    assert MapSet.new(["a", "b"]) == Node.get(node, %{key1: "b", key2: "a"})
    assert MapSet.new(["a", "c"]) == Node.get(node, %{key1: "a", key2: "c"})
    assert MapSet.new(["a", "b", "c"]) == Node.get(node, %{key1: "b", key2: "c"})
  end
end
