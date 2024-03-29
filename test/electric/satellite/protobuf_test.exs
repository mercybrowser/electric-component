defmodule Electric.Postgres.PBTest do
  use Electric.Satellite.Protobuf
  use ExUnit.Case, async: true

  describe "Decode and encode work correctly" do
    test "message for SatRpcRequest is encoded and decoded" do
      original_msg = %SatRpcRequest{method: "test", request_id: 1}
      {:ok, type, iodata} = PB.encode(original_msg)
      {:ok, decoded_msg} = PB.decode(type, :erlang.iolist_to_binary(iodata))
      assert original_msg == decoded_msg
    end

    test "message for transaction" do
      begin = %SatOpBegin{
        commit_timestamp: :os.system_time(:millisecond),
        trans_id: "",
        lsn: "234234"
      }

      data1 = %SatOpInsert{
        relation_id: 10,
        row_data: %SatOpRow{
          nulls_bitmask: <<0::1, 0::1, 0::1, 0::5>>,
          values: [<<"1">>, <<"2">>, <<"10">>]
        }
      }

      data2 = %SatOpUpdate{
        relation_id: 10,
        row_data: %SatOpRow{
          nulls_bitmask: <<0::1, 0::1, 0::1, 0::5>>,
          values: [<<"1">>, <<"2">>, <<"10">>]
        },
        old_row_data: %SatOpRow{
          nulls_bitmask: <<0::1, 0::1, 0::1, 0::5>>,
          values: [<<"21">>, <<"22">>, <<"101">>]
        }
      }

      data3 = %SatOpDelete{
        relation_id: 10,
        old_row_data: %SatOpRow{
          nulls_bitmask: <<0::1, 0::1, 0::1, 0::5>>,
          values: [<<"21">>, <<"22">>, <<"101">>]
        }
      }

      commit = %SatOpCommit{
        commit_timestamp: :os.system_time(:millisecond),
        trans_id: "",
        lsn: "245242342"
      }

      original_msg = %SatOpLog{
        ops: [
          %SatTransOp{op: {:begin, begin}},
          %SatTransOp{op: {:insert, data1}},
          %SatTransOp{op: {:update, data2}},
          %SatTransOp{op: {:delete, data3}},
          %SatTransOp{op: {:commit, commit}}
        ]
      }

      {:ok, type, iodata} = PB.encode(original_msg)

      {:ok, decoded_msg} =
        PB.decode(
          type,
          :erlang.iolist_to_binary(iodata)
        )

      assert original_msg == decoded_msg
    end
  end
end
