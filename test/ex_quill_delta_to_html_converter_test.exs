defmodule ExQuillDeltaToHtmlConverterTest do
  use ExUnit.Case
  doctest ExQuillDeltaToHtmlConverter

  test "should convert walnut example to html" do
    # example_json = "[{\"insert\":\"Click \\\"\",\"attributes\":{\"size\":\"large\"}},{\"insert\":\"Install Now\\\"\",\"attributes\":{\"bold\":true,\"size\":\"large\"}},{\"insert\":\"and\",\"attributes\":{\"size\":\"large\"}},{\"insert\":\" \",\"attributes\":{\"bold\":true,\"size\":\"large\"}},{\"insert\":{\"pre-sized-image\":{\"width\":\"18\",\"imageUrl\":\"https://walnutinc-res.cloudinary.com/image/upload/v1701377473/51c55746-7d9f-4c8d-881c-e7f1b4f103c9/ixtxyub7mrrc3cgvwkzy.jpg\",\"aspectRatio\":\"1.64706 / 1\"}},\"attributes\":{\"bold\":true,\"size\":\"large\",\"color\":\"#0066cc\"}},{\"insert\":\"BriefCatch\",\"attributes\":{\"bold\":true,\"size\":\"large\",\"color\":\"#0066cc\"}},{\"insert\":\" will redirect you to Microsoft Word. \",\"attributes\":{\"size\":\"large\"}},{\"insert\":\"\"},{\"insert\":\"You may receive a notification like the one below asking if you'd like to open Microsoft Word. \",\"attributes\":{\"size\":\"large\"}},{\"insert\":\"\"},{\"insert\":{\"pre-sized-image\":{\"width\":\"868\",\"imageUrl\":\"https://walnutinc-res.cloudinary.com/image/upload/v1701209793/51c55746-7d9f-4c8d-881c-e7f1b4f103c9/yhwd5mvjkimhga24mdww.jpg\",\"aspectRatio\":\"4.59259 / 1\"}},\"attributes\":{\"size\":\"large\"}},{\"insert\":\"Make sure you have Microsoft Word installed then click \\\"\",\"attributes\":{\"size\":\"large\"}},{\"insert\":\"Allow\\\"\",\"attributes\":{\"bold\":true,\"size\":\"large\"}},{\"insert\":\"\"}]"
    # example = Jason.decode!(example_json)
    ops = [
      %ExQuillDeltaToHtmlConverter.DeltaInsertOp{
        insert: %ExQuillDeltaToHtmlConverter.InsertData{type: :text, value: "Hello, "}
      },
      %ExQuillDeltaToHtmlConverter.DeltaInsertOp{
        insert: %ExQuillDeltaToHtmlConverter.InsertData{type: :text, value: "world!"},
        attributes: %{bold: true}
      },
      %ExQuillDeltaToHtmlConverter.DeltaInsertOp{
        insert: %ExQuillDeltaToHtmlConverter.InsertData{type: :text, value: "\n"}
      },
      %ExQuillDeltaToHtmlConverter.DeltaInsertOp{
        insert: %ExQuillDeltaToHtmlConverter.InsertData{type: :image, value: "https://example.com/image.jpg"},
        attributes: %{width: "100%"}
      },
      %ExQuillDeltaToHtmlConverter.DeltaInsertOp{
        insert: %ExQuillDeltaToHtmlConverter.InsertData{type: :text, value: "\n"}
      },
      %ExQuillDeltaToHtmlConverter.DeltaInsertOp{
        insert: %ExQuillDeltaToHtmlConverter.InsertData{type: :text, value: "Check out my website: "}
      },
      %ExQuillDeltaToHtmlConverter.DeltaInsertOp{
        insert: %ExQuillDeltaToHtmlConverter.InsertData{type: :text, value: "https://example.com"},
        attributes: %{link: "https://example.com"}
      },
      %ExQuillDeltaToHtmlConverter.DeltaInsertOp{
        insert: %ExQuillDeltaToHtmlConverter.InsertData{type: :text, value: "\n"}
      }
    ]
    html = ExQuillDeltaToHtmlConverter.convert(ops)
    # html = ExQuillDeltaToHtmlConverter.convert(example)
    IO.inspect(html)
  end

end
