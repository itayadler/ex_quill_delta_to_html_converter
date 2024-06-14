defmodule ExQuillDeltaToHtmlConverterTest do
  use ExUnit.Case

  test "should convert complex example to html" do
    example_json = "[{\"insert\":\"Click \\\"\",\"attributes\":{\"size\":\"large\"}},{\"insert\":\"Install Now\\\"\",\"attributes\":{\"bold\":true,\"size\":\"large\"}},{\"insert\":\"and\",\"attributes\":{\"size\":\"large\"}},{\"insert\":\" \",\"attributes\":{\"bold\":true,\"size\":\"large\"}},{\"insert\":{\"pre-sized-image\":{\"width\":\"18\",\"imageUrl\":\"https://walnutinc-res.cloudinary.com/image/upload/v1701377473/51c55746-7d9f-4c8d-881c-e7f1b4f103c9/ixtxyub7mrrc3cgvwkzy.jpg\",\"aspectRatio\":\"1.64706 / 1\"}},\"attributes\":{\"bold\":true,\"size\":\"large\",\"color\":\"#0066cc\"}},{\"insert\":\"BriefCatch\",\"attributes\":{\"bold\":true,\"size\":\"large\",\"color\":\"#0066cc\"}},{\"insert\":\" will redirect you to Microsoft Word. \",\"attributes\":{\"size\":\"large\"}},{\"insert\":\"\"},{\"insert\":\"You may receive a notification like the one below asking if you'd like to open Microsoft Word. \",\"attributes\":{\"size\":\"large\"}},{\"insert\":\"\"},{\"insert\":{\"pre-sized-image\":{\"width\":\"868\",\"imageUrl\":\"https://walnutinc-res.cloudinary.com/image/upload/v1701209793/51c55746-7d9f-4c8d-881c-e7f1b4f103c9/yhwd5mvjkimhga24mdww.jpg\",\"aspectRatio\":\"4.59259 / 1\"}},\"attributes\":{\"size\":\"large\"}},{\"insert\":\"Make sure you have Microsoft Word installed then click \\\"\",\"attributes\":{\"size\":\"large\"}},{\"insert\":\"Allow\\\"\",\"attributes\":{\"bold\":true,\"size\":\"large\"}},{\"insert\":\"\"}]"
    example = Jason.decode!(example_json, keys: :atoms)
    html = QuillDeltaToHtml.convert(example)
    IO.inspect(html)
    # html_output =
    #   insert_ops
    #   |> Enum.map(&OpToHtmlConverter.convert(&1))
    #   |> Enum.join("")
    # assert html_output == "<span></span><span>Allow\"</span><span>Make sure you have Microsoft Word installed then click \"</span><img size=\"large\" src=\"https://walnutinc-res.cloudinary.com/image/upload/v1701209793/51c55746-7d9f-4c8d-881c-e7f1b4f103c9/yhwd5mvjkimhga24mdww.jpg\"/><span></span><span>You may receive a notification like the one below asking if you'd like to open Microsoft Word. </span><span></span><span> will redirect you to Microsoft Word. </span><span>BriefCatch</span><img bold=\"true\" color=\"#0066cc\" size=\"large\" src=\"https://walnutinc-res.cloudinary.com/image/upload/v1701377473/51c55746-7d9f-4c8d-881c-e7f1b4f103c9/ixtxyub7mrrc3cgvwkzy.jpg\"/><span> </span><span>and</span><span>Install Now\"</span><span>Click \"</span>"
  end

end
