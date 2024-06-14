defmodule QuillDeltaToHtml.InlineGroup do
  defstruct ops: []

  def new(ops \\ []) do
    %__MODULE__{ops: ops}
  end
end

defmodule QuillDeltaToHtml.SingleItem do
  defstruct op: nil

  def new(op) do
    %__MODULE__{op: op}
  end
end

defmodule QuillDeltaToHtml.VideoItem do
  defstruct op: nil

  def new(op) do
    %__MODULE__{op: op}
  end
end

defmodule QuillDeltaToHtml.BlotBlock do
  defstruct op: nil

  def new(op) do
    %__MODULE__{op: op}
  end
end

defmodule QuillDeltaToHtml.BlockGroup do
  defstruct op: nil, ops: []

  def new(op, ops \\ []) do
    %__MODULE__{op: op, ops: ops}
  end
end

defmodule QuillDeltaToHtml.ListGroup do
  defstruct items: []

  def new(items \\ []) do
    %__MODULE__{items: items}
  end
end

defmodule QuillDeltaToHtml.ListItem do
  defstruct item: nil, inner_list: nil

  def new(item, inner_list \\ nil) do
    %__MODULE__{item: item, inner_list: inner_list}
  end
end

defmodule QuillDeltaToHtml.TableGroup do
  defstruct rows: []

  def new(rows \\ []) do
    %__MODULE__{rows: rows}
  end
end

defmodule QuillDeltaToHtml.TableRow do
  defstruct cells: []

  def new(cells \\ []) do
    %__MODULE__{cells: cells}
  end
end

defmodule QuillDeltaToHtml.TableCell do
  defstruct item: nil

  def new(item) do
    %__MODULE__{item: item}
  end
end

defmodule QuillDeltaToHtml.InsertOpDenormalizer do
  alias QuillDeltaToHtml.ValueTypes, as: VT

  def denormalize(%{} = op) do
    case op do
      %{insert: insert} when is_binary(insert) ->
        insert
        |> String.split("\n", keep: true)
        |> Enum.map(fn line ->
          if line == "\n" do
            %{op | insert: VT.new_line()}
          else
            %{op | insert: line}
          end
        end)

      _ ->
        [op]
    end
  end

  def denormalize(_), do: []
end

defmodule QuillDeltaToHtml.InsertDataQuill do
  defstruct type: nil, value: nil
end

defmodule QuillDeltaToHtml.InsertDataCustom do
  defstruct type: nil, value: nil
end

defmodule QuillDeltaToHtml.InsertOpsConverter do
  alias QuillDeltaToHtml.DeltaInsertOp
  alias QuillDeltaToHtml.OpAttributeSanitizer
  alias QuillDeltaToHtml.OpLinkSanitizer
  alias QuillDeltaToHtml.InsertOpDenormalizer
  alias QuillDeltaToHtml.ValueTypes, as: VT
  alias QuillDeltaToHtml.InsertDataQuill
  alias QuillDeltaToHtml.InsertDataCustom

  def convert(delta_ops, options) when is_list(delta_ops) do
    delta_ops
    |> Enum.flat_map(&InsertOpDenormalizer.denormalize/1)
    |> Enum.reduce([], fn op, acc ->
      case op do
        %{insert: insert} ->
          insert_val = convert_insert_val(insert, options)

          case insert_val do
            nil ->
              acc

            _ ->
              attributes = OpAttributeSanitizer.sanitize(op[:attributes], options)
              [DeltaInsertOp.new(insert_val, attributes) | acc]
          end

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  def convert(_, _), do: []

  def convert_insert_val(insert_prop_val, _sanitize_options) when is_binary(insert_prop_val) do
    %InsertDataQuill{type: VT.DataType.Text, value: insert_prop_val}
  end

  def convert_insert_val(insert_prop_val, sanitize_options) when is_map(insert_prop_val) do
    case insert_prop_val do
      %{VT.DataType.Image => image_val} ->
        sanitized_val =
          OpLinkSanitizer.sanitize(to_string(image_val), sanitize_options)

        %InsertDataQuill{type: VT.DataType.Image, value: sanitized_val}

      %{VT.DataType.Video => video_val} ->
        sanitized_val =
          OpLinkSanitizer.sanitize(to_string(video_val), sanitize_options)

        %InsertDataQuill{type: VT.DataType.Video, value: sanitized_val}

      %{VT.DataType.Formula => formula_val} ->
        %InsertDataQuill{type: VT.DataType.Formula, value: formula_val}

      _ ->
        [{type, value}] = Map.to_list(insert_prop_val)
        %InsertDataCustom{type: type, value: value}
    end
  end

  def convert_insert_val(_, _), do: nil
end

defmodule QuillDeltaToHtml.OpAttributeSanitizer do
  alias QuillDeltaToHtml.ValueTypes
  alias QuillDeltaToHtml.OpLinkSanitizer
  alias QuillDeltaToHtml.Mentions.MentionSanitizer

  def sanitize(dirty_attrs, sanitize_options) when is_map(dirty_attrs) do
    clean_attrs = %{}

    Enum.reduce(dirty_attrs, clean_attrs, fn {key, value}, acc ->
      case key do
        :bold ->
          Map.put(acc, :bold, !!value)

        :italic ->
          Map.put(acc, :italic, !!value)

        :underline ->
          Map.put(acc, :underline, !!value)

        :strike ->
          Map.put(acc, :strike, !!value)

        :code ->
          Map.put(acc, :code, !!value)

        :blockquote ->
          Map.put(acc, :blockquote, !!value)

        :"code-block" ->
          Map.put(acc, :"code-block", sanitize_code_block(value))

        :renderAsBlock ->
          Map.put(acc, :renderAsBlock, !!value)

        :background ->
          sanitize_color(acc, :background, value)

        :color ->
          sanitize_color(acc, :color, value)

        :font when is_binary(value) ->
          if valid_font_name?(value), do: Map.put(acc, :font, value), else: acc

        :size when is_binary(value) ->
          if valid_size?(value), do: Map.put(acc, :size, value), else: acc

        :width when is_binary(value) ->
          if valid_width?(value), do: Map.put(acc, :width, value), else: acc

        :link when is_binary(value) ->
          Map.put(acc, :link, OpLinkSanitizer.sanitize(value, sanitize_options))

        :target when is_binary(value) ->
          if valid_target?(value), do: Map.put(acc, :target, value), else: acc

        :rel when is_binary(value) ->
          if valid_rel?(value), do: Map.put(acc, :rel, value), else: acc

        :script when value in [ValueTypes.ScriptType.Sub, ValueTypes.ScriptType.Super] ->
          Map.put(acc, :script, value)

        :list
        when value in [
               ValueTypes.ListType.Bullet,
               ValueTypes.ListType.Ordered,
               ValueTypes.ListType.Checked,
               ValueTypes.ListType.Unchecked
             ] ->
          Map.put(acc, :list, value)

        :header when is_number(value) ->
          Map.put(acc, :header, min(value, 6))

        :align
        when value in [
               ValueTypes.AlignType.Center,
               ValueTypes.AlignType.Right,
               ValueTypes.AlignType.Justify,
               ValueTypes.AlignType.Left
             ] ->
          Map.put(acc, :align, value)

        :direction when value == ValueTypes.DirectionType.Rtl ->
          Map.put(acc, :direction, value)

        :indent when is_number(value) ->
          Map.put(acc, :indent, min(value, 30))

        :mentions when value ->
          if is_map(acc[:mention]) do
            sanitized_mention = MentionSanitizer.sanitize(acc[:mention], sanitize_options)

            if Map.keys(sanitized_mention) != [] do
              Map.merge(acc, %{mentions: !!value, mention: sanitized_mention})
            else
              acc
            end
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  def sanitize(_, _), do: %{}

  defp sanitize_color(acc, key, value) when is_binary(value) do
    cond do
      valid_hex_color?(value) or valid_color_literal?(value) or valid_rgb_color?(value) ->
        Map.put(acc, key, value)

      true ->
        acc
    end
  end

  defp sanitize_color(acc, _, _), do: acc

  defp sanitize_code_block(value) when is_boolean(value), do: value

  defp sanitize_code_block(value) when is_binary(value) do
    if valid_lang?(value) do
      value
    else
      nil
    end
  end

  defp sanitize_code_block(_), do: nil

  defp valid_hex_color?(color_str),
    do: Regex.match?(~r/^#([0-9A-F]{6}|[0-9A-F]{3})$/i, color_str) != nil

  defp valid_color_literal?(color_str), do: Regex.match?(~r/^[a-z]{1,50}$/i, color_str) != nil

  defp valid_rgb_color?(color_str),
    do:
      Regex.match?(
        ~r/^rgb\(((0|25[0-5]|2[0-4]\d|1\d\d|0?\d?\d),\s*){2}(0|25[0-5]|2[0-4]\d|1\d\d|0?\d?\d)\)$/i,
        color_str
      ) != nil

  defp valid_font_name?(font_name), do: Regex.match?(~r/^[a-z\s0-9\- ]{1,30}$/i, font_name) != nil
  defp valid_size?(size), do: Regex.match?(~r/^[a-z0-9\-]{1,20}$/i, size) != nil
  defp valid_width?(width), do: Regex.match?(~r/^[0-9]*(px|em|%)?$/, width) != nil
  defp valid_target?(target), do: target in ["_self", "_blank", "_parent", "_top"]
  defp valid_rel?(rel_str), do: Regex.match?(~r/^[a-zA-Z\s\-]{1,250}$/i, rel_str) != nil
  defp valid_lang?(lang), do: Regex.match?(~r/^[a-zA-Z\s\-\\\/\+]{1,50}$/i, lang) != nil
end

defmodule QuillDeltaToHtml.OpLinkSanitizer do
  alias QuillDeltaToHtml.Funcs.Html, as: FuncsHtml

  def sanitize(link, url_sanitizer, _options) when is_function(url_sanitizer) do
    # Call the passed function with `.(link)`
    case url_sanitizer.(link) do
      nil -> FuncsHtml.encode_link(sanitize_link(link))
      result -> result
    end
  end

  def sanitize(link, _options), do: FuncsHtml.encode_link(sanitize_link(link))

  defp sanitize_link(str) do
    str
    |> String.trim_leading()
    |> then(fn val ->
      if Regex.match?(~r/^((https?|s?ftp|file|blob|mailto|tel):|#|\/|data:image\/)/, val) do
        val
      else
        "unsafe:#{val}"
      end
    end)
  end
end

defmodule QuillDeltaToHtml.OpToHtmlConverter do
  alias QuillDeltaToHtml.DeltaInsertOp
  alias QuillDeltaToHtml.ValueTypes
  alias QuillDeltaToHtml.Funcs.Html, as: FuncsHtml

  defstruct op: nil, options: nil

  def new(op, options \\ nil) do
    default_options = [
      class_prefix: "ql",
      inline_styles: nil,
      encode_html: true,
      list_item_tag: "li",
      paragraph_tag: "p"
    ]

    options =
      case options do
        nil -> default_options
        _ -> Keyword.merge(default_options, Enum.into(options, []))
      end

    %__MODULE__{op: op, options: options}
  end

  def prefix_class(%__MODULE__{options: %{class_prefix: nil}} = _this, class_name),
    do: to_string(class_name)

  def prefix_class(%__MODULE__{options: %{class_prefix: class_prefix}}, class_name) do
    "#{class_prefix}-#{class_name}"
  end

  def get_html(%__MODULE__{} = this) do
    %{opening_tag: opening_tag, content: content, closing_tag: closing_tag} =
      get_html_parts(this)

    opening_tag <> content <> closing_tag
  end

  def get_html_parts(%__MODULE__{op: op} = this) do
    cond do
      op.insert == ValueTypes.new_line() and not DeltaInsertOp.is_container_block?(op) ->
        %{opening_tag: "", closing_tag: "", content: ValueTypes.new_line()}

      true ->
        tags = get_tags(this)
        attrs = get_tag_attributes(this)

        tags = if Enum.empty?(tags) and not Enum.empty?(attrs), do: ["span"], else: tags

        {begin_tags, end_tags} =
          Enum.reduce(tags, {[], []}, fn tag, {begin_tags, end_tags} ->
            if tag == "img" and op.attributes[:link] do
              {
                ["<a#{build_attributes(get_link_attrs(this))}>" | begin_tags],
                ["</a>" | end_tags]
              }
            else
              {
                ["<#{tag}#{build_attributes(attrs)}>" | begin_tags],
                [if(tag == "img", do: "", else: "</#{tag}>") | end_tags]
              }
            end
          end)

        %{
          opening_tag: Enum.join(begin_tags),
          content: get_content(this),
          closing_tag: Enum.join(Enum.reverse(end_tags))
        }
    end
  end

  def get_content(%__MODULE__{op: op, options: options}) do
    cond do
      DeltaInsertOp.is_container_block?(op) ->
        ""

      DeltaInsertOp.is_mentions?(op) ->
        op.insert.value

      DeltaInsertOp.is_formula?(op) or DeltaInsertOp.is_text?(op) ->
        if options[:encode_html],
          do: FuncsHtml.encode_html(op.insert.value),
          else: op.insert.value

      true ->
        ""
    end
  end

  def get_css_classes(%__MODULE__{op: op, options: options} = this) do
    attrs = op.attributes

    cond do
      options[:inline_styles] ->
        []

      true ->
        props =
          if options[:allow_background_classes],
            do: ["indent", "align", "direction", "font", "size", "background"],
            else: ["indent", "align", "direction", "font", "size"]

        custom_classes = get_custom_css_classes(this) || []

        Enum.reduce(props, custom_classes, fn prop, acc ->
          case attrs[prop] do
            nil ->
              acc

            value when prop == "background" and is_binary(value) ->
              if valid_color_literal?(value) do
                [prefix_class(this, "#{prop}-#{value}") | acc]
              else
                acc
              end

            value ->
              [prefix_class(this, "#{prop}-#{value}") | acc]
          end
        end) ++
          if(DeltaInsertOp.is_formula?(op), do: [prefix_class(this, "formula")], else: []) ++
          if(DeltaInsertOp.is_video?(op), do: [prefix_class(this, "video")], else: []) ++
          if(DeltaInsertOp.is_image?(op), do: [prefix_class(this, "image")], else: [])
    end
  end

  def get_css_styles(%__MODULE__{op: op, options: options} = this) do
    attrs = op.attributes

    props =
      if options[:inline_styles] != nil or not options[:allow_background_classes] == nil,
        do: [["color"], ["background", "background-color"]],
        else: [["color"]]

    props =
      if options[:inline_styles] != nil,
        do:
          props ++
            [
              ["indent"],
              ["align", "text-align"],
              ["direction"],
              ["font", "font-family"],
              ["size"]
            ],
        else: props

    (get_custom_css_styles(this) || []) ++
      Enum.reduce(props, [], fn item, acc ->
        case attrs[item |> hd()] do
          nil ->
            acc

          attr_value ->
            attribute_converter =
              case options[:inline_styles] do
                nil ->
                  case item |> hd() do
                    :font ->
                      fn value, _op ->
                        case value do
                          "serif" -> "font-family: Georgia, Times New Roman, serif"
                          "monospace" -> "font-family: Monaco, Courier New, monospace"
                          _ -> "font-family:#{value}"
                        end
                      end

                    :size ->
                      fn
                        "small", _op -> "font-size: 0.75em"
                        "large", _op -> "font-size: 1.5em"
                        "huge", _op -> "font-size: 2.5em"
                        _, _op -> nil
                      end

                    :indent ->
                      fn value, op ->
                        indent_size = String.to_integer(value) * 3
                        side = if op.attributes[:direction] == "rtl", do: "right", else: "left"
                        "padding-#{side}: #{indent_size}em"
                      end

                    :direction ->
                      fn
                        "rtl", op ->
                          "direction:rtl" <>
                            if(op.attributes[:align], do: "", else: "; text-align:inherit")

                        _, _op ->
                          nil
                      end

                    _ ->
                      nil
                  end

                styles ->
                  Map.get(styles, item |> hd())
              end

            style =
              case attribute_converter do
                %{} = map -> map[attr_value]
                nil -> "#{Enum.at(item, 1) || Enum.at(item, 0)}: #{attr_value}"
                _ -> attribute_converter.(attr_value, op)
              end

            if style, do: [style | acc], else: acc
        end
      end)
  end

  def get_tag_attributes(%__MODULE__{op: op, options: _options} = this) do
    cond do
      op.attributes[:code] != nil and not DeltaInsertOp.is_link?(op) ->
        []

      DeltaInsertOp.is_image?(op) ->
        (get_custom_tag_attributes(this) || []) ++
          if(op.attributes[:width], do: [{:width, op.attributes[:width]}], else: []) ++
          [{:src, op.insert.value}]

      DeltaInsertOp.is_a_check_list?(op) ->
        (get_custom_tag_attributes(this) || []) ++
          [{:data_checked, if(DeltaInsertOp.is_checked_list?(op), do: "true", else: "false")}]

      DeltaInsertOp.is_formula?(op) ->
        get_custom_tag_attributes(this) || []

      DeltaInsertOp.is_video?(op) ->
        (get_custom_tag_attributes(this) || []) ++
          [{:frameborder, "0"}, {:allowfullscreen, "true"}, {:src, op.insert.value}]

      DeltaInsertOp.is_mentions?(op) ->
        mention = op.attributes[:mention]

        (get_custom_tag_attributes(this) || []) ++
          if(mention[:class], do: [{:class, mention[:class]}], else: []) ++
          if(mention["end-point"] && mention[:slug],
            do: [{:href, "#{mention["end-point"]}/#{mention[:slug]}"}],
            else: [{:href, "about:blank"}]
          ) ++
          if(mention[:target], do: [{:target, mention[:target]}], else: [])

      true ->
        custom_attrs = get_custom_tag_attributes(this) || []
        classes = get_css_classes(this)

        tag_attrs =
          if classes != [],
            do: custom_attrs ++ [{:class, Enum.join(classes, " ")}],
            else: custom_attrs

        tag_attrs =
          if DeltaInsertOp.is_code_block?(op) and is_binary(op.attributes[:"code-block"]),
            do: tag_attrs ++ [{:data_language, op.attributes[:"code-block"]}],
            else: tag_attrs

        tag_attrs =
          if DeltaInsertOp.is_container_block?(op) do
            tag_attrs
          else
            if DeltaInsertOp.is_link?(op),
              do: tag_attrs ++ get_link_attrs(this),
              else: tag_attrs
          end

        styles = get_css_styles(this)

        if styles != [],
          do: tag_attrs ++ [{:style, Enum.join(styles, ";")}],
          else: tag_attrs
    end
  end

  def get_link_attrs(%__MODULE__{op: op, options: options}) do
    target_for_all =
      if options[:link_target] and valid_target?(options[:link_target]),
        do: options[:link_target],
        else: nil

    rel_for_all =
      if options[:link_rel] and valid_rel?(options[:link_rel]),
        do: options[:link_rel],
        else: nil

    target = op.attributes[:target] || target_for_all
    rel = op.attributes[:rel] || rel_for_all

    [{:href, op.attributes[:link]}] ++
      if(target, do: [{:target, target}], else: []) ++
      if(rel, do: [{:rel, rel}], else: [])
  end

  def get_custom_tag(%__MODULE__{op: op, options: options} = _this, format) do
    custom_tag = options[:custom_tag]

    if is_function(custom_tag) do
      custom_tag.(format, op)
    else
      nil
    end
  end

  def get_custom_tag_attributes(%__MODULE__{op: op, options: options} = _this) do
    custom_tag_attributes = options[:custom_tag_attributes]

    if is_function(custom_tag_attributes) do
      custom_tag_attributes.(op)
    else
      nil
    end
  end

  def get_custom_css_classes(%__MODULE__{op: op, options: options} = _this) do
    custom_css_classes = options[:custom_css_classes]

    if is_function(custom_css_classes) do
      case custom_css_classes.(op) do
        nil -> nil
        res when is_list(res) -> res
        res -> [res]
      end
    else
      nil
    end
  end

  def get_custom_css_styles(%__MODULE__{op: op, options: options} = _this) do
    custom_css_styles = options[:custom_css_styles]

    if is_function(custom_css_styles) do
      case custom_css_styles.(op) do
        nil -> nil
        res when is_list(res) -> res
        res -> [res]
      end
    else
      nil
    end
  end

  def get_tags(%__MODULE__{op: op, options: options} = this) do
    attrs = op.attributes

    cond do
      not DeltaInsertOp.is_text?(op) ->
        case true do
          # Match any non-text op
          true ->
            cond do
              DeltaInsertOp.is_video?(op) -> ["iframe"]
              DeltaInsertOp.is_image?(op) -> ["img"]
              # Default for other embed types
              true -> ["span"]
            end
        end

      true ->
        position_tag = options[:paragraph_tag] || "p"

        blocks = [
          ["blockquote", nil],
          [:"code-block", "pre"],
          [:list, options[:list_item_tag]],
          [:header, nil],
          [:align, position_tag],
          [:direction, position_tag],
          [:indent, position_tag]
        ]

        case Enum.find(blocks, fn [key, _value] -> attrs[key] != nil end) do
          nil ->
            if DeltaInsertOp.is_custom_text_block?(op) do
              case get_custom_tag(this, "renderAsBlock") do
                nil -> [position_tag]
                tag -> [tag]
              end
            else
              inlines = [
                [:link, "a"],
                [:mentions, "a"],
                [:script, nil],
                [:bold, "strong"],
                [:italic, "em"],
                [:strike, "s"],
                [:underline, "u"],
                [:code, nil]
              ]

              custom_tags_map =
                Enum.reduce(attrs, %{}, fn {key, _value}, acc ->
                  case get_custom_tag(this, key) do
                    nil -> acc
                    tag -> Map.put(acc, key, tag)
                  end
                end)

              for(
                [key, value] <- inlines,
                attrs[key] != nil,
                do: Map.get(custom_tags_map, key, value)
              ) ++
                for {key, value} <- custom_tags_map,
                    Enum.all?(inlines, fn [k, _v] -> k != key end),
                    do: value
            end

          [key, value] ->
            case key do
              :header ->
                ["h#{attrs[:header]}"]

              _ ->
                case get_custom_tag(this, key) do
                  nil -> [value || key]
                  tag -> [tag]
                end
            end
        end
    end
  end

  defp build_attributes(attrs) do
    Enum.map(attrs, fn {key, value} ->
      " #{key}=\"#{value}\""
    end)
    |> Enum.join()
  end

  defp valid_color_literal?(color_str), do: Regex.match?(~r/^[a-z]{1,50}$/i, color_str) != nil
  defp valid_target?(target), do: target in ["_self", "_blank", "_parent", "_top"]
  defp valid_rel?(rel_str), do: Regex.match?(~r/^[a-zA-Z\s\-]{1,250}$/i, rel_str) != nil
end

defmodule QuillDeltaToHtml.QuillDeltaToHtmlConverter do
  alias QuillDeltaToHtml.InsertOpsConverter
  alias QuillDeltaToHtml.OpToHtmlConverter
  alias QuillDeltaToHtml.DeltaInsertOp
  alias QuillDeltaToHtml.Grouper
  alias QuillDeltaToHtml.ListNester
  alias QuillDeltaToHtml.Funcs.Html, as: FuncsHtml
  alias QuillDeltaToHtml.ValueTypes
  alias QuillDeltaToHtml.TableGrouper

  defstruct options: nil,
            raw_delta_ops: [],
            converter_options: nil,
            callbacks: %{}

  def new(delta_ops, options \\ nil) do
    default_options = %{
      paragraph_tag: "p",
      encode_html: true,
      class_prefix: "ql",
      inline_styles: false,
      multi_line_blockquote: true,
      multi_line_header: true,
      multi_line_codeblock: true,
      multi_line_paragraph: true,
      multi_line_custom_block: true,
      allow_background_classes: false,
      link_target: "_blank",
      ordered_list_tag: "ol",
      bullet_list_tag: "ul",
      list_item_tag: "li"
    }

    options =
      case options do
        nil -> default_options
        _ -> Keyword.merge(default_options, options)
      end

    inline_styles =
      case options[:inline_styles] do
        false -> nil
        styles when is_map(styles) -> styles
        _ -> %{}
      end

    converter_options = %{
      encode_html: options[:encode_html],
      class_prefix: options[:class_prefix],
      inline_styles: inline_styles,
      list_item_tag: options[:list_item_tag],
      paragraph_tag: options[:paragraph_tag],
      link_rel: options[:link_rel],
      link_target: options[:link_target],
      allow_background_classes: options[:allow_background_classes],
      custom_tag: options[:custom_tag],
      custom_tag_attributes: options[:custom_tag_attributes],
      custom_css_classes: options[:custom_css_classes],
      custom_css_styles: options[:custom_css_styles]
    }

    %__MODULE__{
      options: options,
      raw_delta_ops: delta_ops,
      converter_options: converter_options
    }
  end

  def _get_list_tag(%{options: %{ordered_list_tag: ordered_list_tag}} = op),
    do: if(DeltaInsertOp.is_ordered_list?(op), do: ordered_list_tag, else: "")

  def _get_list_tag(%{options: %{bullet_list_tag: bullet_list_tag}} = op),
    do:
      if(
        DeltaInsertOp.is_bullet_list?(op) or DeltaInsertOp.is_checked_list?(op) or
          DeltaInsertOp.is_unchecked_list?(op),
        do: bullet_list_tag,
        else: ""
      )

  def _get_list_tag(_op), do: ""

  def get_grouped_ops(%__MODULE__{raw_delta_ops: raw_delta_ops, options: options} = _this) do
    raw_delta_ops
    |> InsertOpsConverter.convert(options)
    |> Grouper.pair_ops_with_their_block()
    |> Grouper.group_consecutive_same_style_blocks(
      blockquotes: options[:multi_line_blockquote],
      header: options[:multi_line_header],
      codeBlocks: options[:multi_line_codeblock],
      customBlocks: options[:multi_line_custom_block]
    )
    |> Grouper.reduce_consecutive_same_style_blocks_to_one()
    |> TableGrouper.group()
    |> ListNester.nest()
  end

  def convert(%__MODULE__{converter_options: converter_options, callbacks: callbacks} = this) do
    this
    |> get_grouped_ops()
    |> List.flatten()
    |> Enum.map(fn group ->
      case group do
        %QuillDeltaToHtml.ListGroup{} = list_group ->
          render_with_callbacks(callbacks, ValueTypes.GroupType.List, list_group, fn ->
            render_list(list_group, this)
          end)

        %QuillDeltaToHtml.TableGroup{} = table_group ->
          render_with_callbacks(callbacks, ValueTypes.GroupType.Table, table_group, fn ->
            render_table(table_group, this)
          end)

        %QuillDeltaToHtml.BlockGroup{op: op, ops: ops} = block_group ->
          render_with_callbacks(callbacks, ValueTypes.GroupType.Block, block_group, fn ->
            render_block(op, ops, this)
          end)

        %QuillDeltaToHtml.BlotBlock{op: op} = _blot_block ->
          render_custom(op, nil, callbacks)

        %QuillDeltaToHtml.VideoItem{op: op} = video_item ->
          render_with_callbacks(callbacks, ValueTypes.GroupType.Video, video_item, fn ->
            converter = OpToHtmlConverter.new(op, converter_options)
            OpToHtmlConverter.get_html(converter)
          end)

        %QuillDeltaToHtml.InlineGroup{ops: ops} = inline_group ->
          render_with_callbacks(callbacks, ValueTypes.GroupType.InlineGroup, inline_group, fn ->
            render_inlines(ops, true, this)
          end)
      end
    end)
    |> Enum.join()
  end

  defp render_list(list, %__MODULE__{converter_options: converter_options} = this) do
    first_item = List.first(list.items)

    "<#{_get_list_tag(first_item.item.op)}>" <>
      (Enum.map(list.items, fn li -> render_list_item(li, converter_options, this) end)
       |> Enum.join()) <>
      "</#{_get_list_tag(first_item.item.op)}>"
  end

  defp render_list_item(li, converter_options, this) do
    converter = OpToHtmlConverter.new(li.item.op, converter_options)
    %{opening_tag: opening_tag, closing_tag: closing_tag} = converter.get_html_parts()

    opening_tag <>
      render_inlines(li.item.ops, false, this) <>
      if(li.inner_list, do: render_list(li.inner_list, this), else: "") <>
      closing_tag
  end

  defp render_table(table, this) do
    "<table><tbody>" <>
      (Enum.map(table.rows, fn row -> render_table_row(row, this) end) |> Enum.join()) <>
      "</tbody></table>"
  end

  defp render_table_row(row, this) do
    "<tr>" <>
      (Enum.map(row.cells, fn cell -> render_table_cell(cell, this) end) |> Enum.join()) <>
      "</tr>"
  end

  defp render_table_cell(cell, %__MODULE__{converter_options: converter_options} = this) do
    converter = OpToHtmlConverter.new(cell.item.op, converter_options)
    %{opening_tag: opening_tag, closing_tag: closing_tag} = converter.get_html_parts()

    "<td data-row=\"#{cell.item.op.attributes[:table]}\">" <>
      opening_tag <>
      render_inlines(cell.item.ops, false, this) <>
      closing_tag <>
      "</td>"
  end

  defp render_block(bop, ops, %__MODULE__{converter_options: converter_options} = this) do
    converter = OpToHtmlConverter.new(bop, converter_options)
    %{opening_tag: opening_tag, closing_tag: closing_tag} = converter.get_html_parts()

    if DeltaInsertOp.is_code_block?(bop) do
      opening_tag <>
        (ops
         |> Enum.map(fn iop ->
           if DeltaInsertOp.is_custom_embed?(iop),
             do: render_custom(iop, bop, this.callbacks),
             else: iop.insert.value
         end)
         |> Enum.join()
         |> FuncsHtml.encode_html()) <>
        closing_tag
    else
      inlines = Enum.map(ops, &render_inline(&1, bop, this)) |> Enum.join()
      opening_tag <> if(inlines == "", do: "<br/>", else: inlines) <> closing_tag
    end
  end

  defp render_inlines(ops, is_inline_group, %__MODULE__{options: options} = this) do
    ops_len = length(ops) - 1

    html =
      ops
      |> Enum.with_index()
      |> Enum.map(fn {op, i} ->
        if i > 0 and i == ops_len and op.insert == ValueTypes.new_line(),
          do: "",
          else: render_inline(op, nil, this)
      end)
      |> Enum.join()

    if not is_inline_group, do: html

    start_para_tag = "<#{options.paragraph_tag}>"
    end_para_tag = "</#{options.paragraph_tag}>"

    if html == "<br/>" or options.multi_line_paragraph do
      start_para_tag <> html <> end_para_tag
    else
      start_para_tag <>
        (html
         |> String.split("<br/>")
         |> Enum.map(fn v -> if v == "", do: "<br/>", else: v end)
         |> Enum.join(end_para_tag <> start_para_tag)) <> end_para_tag
    end
  end

  defp render_inline(op, context_op, %__MODULE__{
         converter_options: converter_options,
         callbacks: callbacks
       }) do
    cond do
      DeltaInsertOp.is_custom_embed?(op) ->
        render_custom(op, context_op, callbacks)

      true ->
        converter = OpToHtmlConverter.new(op, converter_options)
        OpToHtmlConverter.get_html(converter) |> String.replace("\n", "<br/>")
    end
  end

  defp render_custom(op, context_op, callbacks) do
    case callbacks["renderCustomOp_cb"] do
      render_cb when is_function(render_cb) ->
        render_cb.(op, context_op)

      _ ->
        ""
    end
  end

  def before_render(%__MODULE__{} = this, cb) when is_function(cb) do
    %{this | callbacks: Map.put(this.callbacks, "beforeRender_cb", cb)}
  end

  def after_render(%__MODULE__{} = this, cb) when is_function(cb) do
    %{this | callbacks: Map.put(this.callbacks, "afterRender_cb", cb)}
  end

  def render_custom_with(%__MODULE__{} = this, cb) when is_function(cb) do
    %{this | callbacks: Map.put(this.callbacks, "renderCustomOp_cb", cb)}
  end

  defp render_with_callbacks(callbacks, group_type, group, render_fn) do
    html =
      case callbacks["beforeRender_cb"] do
        before_cb when is_function(before_cb) -> before_cb.(group_type, group)
        _ -> nil
      end

    html = if html, do: html, else: render_fn.()

    case callbacks["afterRender_cb"] do
      after_cb when is_function(after_cb) -> after_cb.(group_type, html)
      _ -> html
    end
  end
end

defmodule QuillDeltaToHtml.Funcs.Html do
  def make_start_tag(tag, attrs \\ nil) do
    attrs_str =
      case attrs do
        nil ->
          ""

        _ ->
          attrs
          |> List.wrap()
          |> Enum.map(fn
            %{key: key} -> " #{key}"
            %{key: key, value: value} -> " #{key}=\"#{value}\""
          end)
          |> Enum.join()
      end

    closing = if tag in ["img", "br"], do: "/>", else: ">"
    "<#{tag}#{attrs_str}#{closing}"
  end

  def make_end_tag(tag), do: "</#{tag}>"

  def decode_html(str), do: encode_mappings(:html) |> Enum.reduce(str, &decode_mapping/2)

  def encode_html(str, prevent_double_encoding \\ true) do
    str =
      if prevent_double_encoding do
        decode_html(str)
      else
        str
      end

    Enum.map(encode_mappings(:html), fn {pattern, replacement} ->
      String.replace(str, pattern, replacement)
    end)

    str
  end

  def encode_link(str),
    do:
      str
      |> Enum.reduce(encode_mappings(:url), &decode_mapping/2)
      |> Enum.reduce(encode_mappings(:url), &encode_mapping/2)

  defp encode_mappings(type) do
    maps = [
      {"&", "&amp;"},
      {"<", "&lt;"},
      {">", "&gt;"},
      {"\"", "&quot;"},
      {"'", "&#x27;"},
      {"\\/", "&#x2F;"},
      {"\\(", "&#40;"},
      {"\\)", "&#41;"}
    ]

    case type do
      :html ->
        Enum.filter(maps, fn {v, _} ->
          String.contains?(v, "(") == false and String.contains?(v, ")") == false
        end)

      :url ->
        Enum.filter(maps, fn {v, _} -> String.contains?(v, "/") == false end)
    end
  end

  defp encode_mapping({pattern, replacement}, str) do
    String.replace(str, ~r/#{pattern}/g, replacement)
  end

  defp decode_mapping({pattern, replacement}, str) do
    replacement_regex = Regex.escape(replacement)
    String.replace(str, ~r/#{replacement_regex}/, pattern |> String.replace("\\", ""))
  end
end

defmodule QuillDeltaToHtml.Grouper do
  alias QuillDeltaToHtml.DeltaInsertOp
  alias QuillDeltaToHtml.VideoItem
  alias QuillDeltaToHtml.InlineGroup
  alias QuillDeltaToHtml.BlockGroup
  alias QuillDeltaToHtml.BlotBlock
  alias QuillDeltaToHtml.ValueTypes

  def pair_ops_with_their_block(ops) do
    Enum.reduce(ops, [], fn op, acc ->
      case {op, acc} do
        {%{insert: ValueTypes.NewLine}, [%InlineGroup{ops: inline_ops} | tail]} ->
          [%InlineGroup{ops: inline_ops ++ [op]} | tail]

        {%{insert: ValueTypes.NewLine}, _} ->
          [%InlineGroup{ops: [op]} | acc]

        {op, [%InlineGroup{ops: inline_ops} | tail]} ->
          if DeltaInsertOp.is_inline?(op) do
            [%InlineGroup{ops: inline_ops ++ [op]} | tail]
          else
            [%InlineGroup{ops: [op]} | acc]
          end

        # No guards here
        {op, _} ->
          cond do
            DeltaInsertOp.is_video?(op) ->
              [VideoItem.new(op) | acc]

            DeltaInsertOp.is_custom_embed_block?(op) ->
              [BlotBlock.new(op) | acc]

            DeltaInsertOp.is_container_block?(op) ->
              [BlockGroup.new(op, [DeltaInsertOp.create_new_line_op()]) | acc]

            # Default case
            true ->
              [%InlineGroup{ops: [op]} | acc]
          end
      end
    end)
    |> Enum.reverse()
  end

  def group_consecutive_same_style_blocks(groups, opts) do
    groups
    |> Enum.reduce([], fn group, acc ->
      case acc do
        [] ->
          [[group]]

        [current_group | rest] ->
          if should_group?(List.last(current_group), group, opts) do
            [[current_group ++ [group]] | rest]
          else
            [[group] | [current_group | rest]]
          end
      end
    end)
    |> Enum.reverse()
  end

  defp should_group?(%BlockGroup{op: op1}, %BlockGroup{op: op2}, opts) do
    (opts[:codeBlocks] and DeltaInsertOp.is_code_block?(op1) and DeltaInsertOp.is_code_block?(op2) and
       DeltaInsertOp.has_same_lang_as?(op1, op2)) or
      (opts[:blockquotes] and DeltaInsertOp.is_blockquote?(op1) and
         DeltaInsertOp.is_blockquote?(op2) and DeltaInsertOp.has_same_adi_as?(op1, op2)) or
      (opts[:header] and DeltaInsertOp.is_same_header_as?(op1, op2) and
         DeltaInsertOp.has_same_adi_as?(op1, op2)) or
      (opts[:customBlocks] and DeltaInsertOp.is_custom_text_block?(op1) and
         DeltaInsertOp.is_custom_text_block?(op2) and DeltaInsertOp.has_same_attr?(op1, op2))
  end

  defp should_group?(_, _, _), do: false

  def reduce_consecutive_same_style_blocks_to_one(groups) do
    new_line_op = DeltaInsertOp.create_new_line_op()

    Enum.map(groups, fn elm ->
      case elm do
        [%BlockGroup{} | _] = block_group ->
          ops =
            block_group
            |> Enum.with_index()
            |> Enum.flat_map(fn {g, i} ->
              cond do
                Enum.empty?(g.ops) ->
                  [new_line_op]

                i < length(block_group) - 1 ->
                  g.ops ++ [new_line_op]

                true ->
                  g.ops
              end
            end)

          %{Enum.at(block_group, 0) | ops: ops}

        _ ->
          elm
      end
    end)
  end
end

defmodule QuillDeltaToHtml.ListNester do
  alias QuillDeltaToHtml.DeltaInsertOp
  alias QuillDeltaToHtml.ListGroup
  alias QuillDeltaToHtml.ListItem
  alias QuillDeltaToHtml.BlockGroup

  def nest(groups) do
    groups
    |> convert_list_blocks_to_list_groups()
    |> group_consecutive_list_groups()
    |> Enum.flat_map(fn group ->
      case group do
        [%ListGroup{} | _] = list_group -> nest_list_section(list_group)
        _ -> [group]
      end
    end)
    |> group_consecutive_elements_while(fn
      %ListGroup{}, %ListGroup{} -> true
      _, _ -> false
    end)
    |> Enum.map(fn group ->
      case group do
        [%ListGroup{} | _] = list_group ->
          items =
            list_group
            |> Enum.map(& &1.items)
            |> List.flatten()

          %ListGroup{items: items}

        _ ->
          group
      end
    end)
  end

  defp convert_list_blocks_to_list_groups(items) do
    Enum.map(
      group_consecutive_elements_while(items, fn
        %BlockGroup{op: op1}, %BlockGroup{op: op2} ->
          if DeltaInsertOp.is_list?(op1) and DeltaInsertOp.is_list?(op2) do
            DeltaInsertOp.is_same_list_as?(op1, op2) and
              DeltaInsertOp.has_same_indentation_as?(op1, op2)
          else
            false
          end

        _, _ ->
          false
      end),
      fn item ->
        case item do
          [%BlockGroup{} | _] = block_group ->
            %ListGroup{items: Enum.map(block_group, &%ListItem{item: &1})}

          # Remove the guard here
          %BlockGroup{op: op} = block_group ->
            if DeltaInsertOp.is_list?(op) do
              %ListGroup{items: [%ListItem{item: block_group}]}
            else
              # Return the item unchanged if it's not a list
              item
            end

          _ ->
            item
        end
      end
    )
  end

  defp group_consecutive_list_groups(items) do
    group_consecutive_elements_while(items, fn
      %ListGroup{}, %ListGroup{} -> true
      _, _ -> false
    end)
  end

  defp nest_list_section(section_items) do
    indent_groups =
      Enum.group_by(section_items, fn %ListGroup{items: items} ->
        List.first(items).item.op.attributes[:indent]
      end)

    Enum.sort(Map.keys(indent_groups), :desc)
    |> Enum.reduce(section_items, fn indent, acc ->
      Enum.reduce(indent_groups[indent], acc, fn lg, acc ->
        idx = Enum.find_index(acc, &(&1 == lg))

        case place_under_parent(lg, Enum.slice(acc, 0, idx)) do
          true -> List.delete_at(acc, idx)
          false -> acc
        end
      end)
    end)
  end

  defp place_under_parent(target, items) do
    Enum.any?(Enum.reverse(items), fn elm ->
      if DeltaInsertOp.has_higher_indent_than?(
           List.first(target.items).item.op,
           List.first(elm.items).item.op
         ) do
        parent = List.last(elm.items)

        if parent.inner_list do
          %{
            parent
            | inner_list: %{parent.inner_list | items: parent.inner_list.items ++ target.items}
          }
        else
          %{parent | inner_list: target}
        end

        true
      else
        false
      end
    end)
  end

  defp group_consecutive_elements_while(list, condition) do
    {acc, current_group} =
      Enum.reduce(list, {[], nil}, fn elem, {acc, current_group} ->
        if current_group == nil do
          {acc, [elem]}
        else
          if condition.(List.last(current_group), elem) do
            {acc, current_group ++ [elem]}
          else
            {acc ++ [current_group], [elem]}
          end
        end
      end)

    case current_group do
      nil -> acc
      _ -> acc ++ [current_group]
    end
  end
end

defmodule QuillDeltaToHtml.TableGrouper do
  alias QuillDeltaToHtml.TableGroup
  alias QuillDeltaToHtml.TableRow
  alias QuillDeltaToHtml.TableCell
  alias QuillDeltaToHtml.BlockGroup
  alias QuillDeltaToHtml.DeltaInsertOp

  def group(groups) do
    groups
    |> convert_table_blocks_to_table_groups()
  end

  defp convert_table_blocks_to_table_groups(items) do
    Enum.map(
      group_consecutive_elements_while(items, fn
        %BlockGroup{op: op1}, %BlockGroup{op: op2} ->
          DeltaInsertOp.is_table?(op1) and DeltaInsertOp.is_table?(op2)

        _, _ ->
          false
      end),
      fn item ->
        case item do
          [%BlockGroup{} | _] = block_group ->
            rows = convert_table_blocks_to_table_rows(block_group)
            %TableGroup{rows: rows}

          # Remove the guard
          %BlockGroup{op: op} = block_group ->
            if DeltaInsertOp.is_table?(op) do
              %TableGroup{rows: [%TableRow{cells: [%TableCell{item: block_group}]}]}
            else
              item
            end

          _ ->
            item
        end
      end
    )
  end

  defp convert_table_blocks_to_table_rows(items) do
    Enum.map(
      group_consecutive_elements_while(items, fn
        %BlockGroup{op: op1}, %BlockGroup{op: op2} ->
          DeltaInsertOp.is_table?(op1) and DeltaInsertOp.is_table?(op2) and
            DeltaInsertOp.is_same_table_row_as?(op1, op2)

        _, _ ->
          false
      end),
      fn item ->
        case item do
          [%BlockGroup{} | _] = block_group ->
            %TableRow{cells: Enum.map(block_group, &%TableCell{item: &1})}

          %BlockGroup{} = block_group ->
            %TableRow{cells: [%TableCell{item: block_group}]}

          _ ->
            item
        end
      end
    )
  end

  defp group_consecutive_elements_while(list, condition) do
    {acc, current_group} =
      Enum.reduce(list, {[], nil}, fn elem, {acc, current_group} ->
        if current_group == nil do
          {acc, [elem]}
        else
          if condition.(List.last(current_group), elem) do
            {acc, current_group ++ [elem]}
          else
            {acc ++ [current_group], [elem]}
          end
        end
      end)

    case current_group do
      nil -> acc
      _ -> acc ++ [current_group]
    end
  end
end

defmodule QuillDeltaToHtml.DeltaInsertOp do
  alias QuillDeltaToHtml.ValueTypes
  defstruct insert: nil, attributes: %{}

  def new(insert, attributes \\ %{}) do
    %__MODULE__{insert: insert, attributes: attributes}
  end

  def create_new_line_op() do
    %__MODULE__{insert: ValueTypes.new_line()}
  end

  def is_container_block?(%__MODULE__{attributes: attrs} = op) do
    attrs[:blockquote] != nil or
      attrs[:list] != nil or
      attrs[:table] != nil or
      attrs[:"code-block"] != nil or
      attrs[:header] != nil or
      is_block_attribute?(op) or
      is_custom_text_block?(op)
  end

  def is_block_attribute?(%__MODULE__{attributes: attrs}) do
    # Handle potential nil attributes
    attrs = attrs || %{}
    attrs[:align] != nil or attrs[:direction] != nil or attrs[:indent] != nil
  end

  def is_blockquote?(%__MODULE__{attributes: attrs}) do
    attrs[:blockquote] != nil
  end

  def is_header?(%__MODULE__{attributes: attrs}) do
    attrs[:header] != nil
  end

  def is_table?(%__MODULE__{attributes: attrs}) do
    attrs[:table] != nil
  end

  def is_same_header_as?(%__MODULE__{attributes: attrs1}, %__MODULE__{attributes: attrs2}) do
    attrs1[:header] == attrs2[:header] and attrs1[:header] != nil
  end

  def has_same_adi_as?(%__MODULE__{attributes: attrs1}, %__MODULE__{attributes: attrs2}) do
    attrs1[:align] == attrs2[:align] and
      attrs1[:direction] == attrs2[:direction] and
      attrs1[:indent] == attrs2[:indent]
  end

  def has_same_indentation_as?(%__MODULE__{attributes: attrs1}, %__MODULE__{attributes: attrs2}) do
    attrs1[:indent] == attrs2[:indent]
  end

  def has_same_attr?(%__MODULE__{attributes: attrs1}, %__MODULE__{attributes: attrs2}) do
    attrs1 == attrs2
  end

  def has_higher_indent_than?(%__MODULE__{attributes: attrs1}, %__MODULE__{attributes: attrs2}) do
    (attrs1[:indent] || 0) > (attrs2[:indent] || 0)
  end

  def is_inline?(%__MODULE__{} = op) do
    not is_container_block?(op) and
      not is_video?(op) and
      not is_custom_embed_block?(op)
  end

  def is_code_block?(%__MODULE__{attributes: attrs}) do
    attrs[:"code-block"] != nil
  end

  def has_same_lang_as?(%__MODULE__{attributes: attrs1}, %__MODULE__{attributes: attrs2}) do
    attrs1[:"code-block"] == attrs2[:"code-block"]
  end

  def is_just_newline?(%__MODULE__{insert: insert}) do
    insert == ValueTypes.new_line()
  end

  def is_list?(%__MODULE__{} = op) do
    is_ordered_list?(op) or
      is_bullet_list?(op) or
      is_checked_list?(op) or
      is_unchecked_list?(op)
  end

  def is_ordered_list?(%__MODULE__{attributes: attrs}) do
    attrs[:list] == ValueTypes.ListType.Ordered
  end

  def is_bullet_list?(%__MODULE__{attributes: attrs}) do
    attrs[:list] == ValueTypes.ListType.Bullet
  end

  def is_checked_list?(%__MODULE__{attributes: attrs}) do
    attrs[:list] == ValueTypes.ListType.Checked
  end

  def is_unchecked_list?(%__MODULE__{attributes: attrs}) do
    attrs[:list] == ValueTypes.ListType.Unchecked
  end

  def is_a_check_list?(%__MODULE__{attributes: attrs}) do
    attrs[:list] == ValueTypes.ListType.Unchecked or attrs[:list] == ValueTypes.ListType.Checked
  end

  def is_same_list_as?(
        %__MODULE__{attributes: attrs1} = op1,
        %__MODULE__{attributes: attrs2} = op2
      ) do
    attrs2[:list] != nil and
      (attrs1[:list] == attrs2[:list] or (is_a_check_list?(op2) and is_a_check_list?(op1)))
  end

  def is_same_table_row_as?(%__MODULE__{attributes: attrs1}, %__MODULE__{attributes: attrs2}) do
    attrs2[:table] != nil and attrs1[:table] != nil and attrs1[:table] == attrs2[:table]
  end

  def is_text?(op) do
    op.insert.type == ValueTypes.DataType.Text
  end

  def is_image?(op) do
    op.insert.type == ValueTypes.DataType.Image
  end

  def is_formula?(op) do
    op.insert.type == ValueTypes.DataType.Formula
  end

  def is_video?(op) do
    op.insert.type == ValueTypes.DataType.Video
  end

  def is_link?(%__MODULE__{} = op) do
    is_text?(op) and op.attributes[:link] != nil
  end

  def is_custom_embed?(%__MODULE__{insert: insert}) do
    is_struct(insert, QuillDeltaToHtml.InsertDataCustom)
  end

  def is_custom_embed_block?(%__MODULE__{} = op) do
    is_custom_embed?(op) and op.attributes[:renderAsBlock] != nil
  end

  def is_custom_text_block?(%__MODULE__{} = op) do
    is_text?(op) and op.attributes[:renderAsBlock] != nil
  end

  def is_mentions?(%__MODULE__{} = op) do
    is_text?(op) and op.attributes[:mentions] != nil
  end
end

defmodule QuillDeltaToHtml.Mentions.MentionSanitizer do
  alias QuillDeltaToHtml.OpLinkSanitizer

  def sanitize(dirty_obj, sanitize_options) when is_map(dirty_obj) do
    clean_obj = %{}

    Enum.reduce(dirty_obj, clean_obj, fn {key, value}, acc ->
      case key do
        :class when is_binary(value) ->
          if valid_class?(value), do: Map.put(acc, :class, value), else: acc

        :id when is_binary(value) ->
          if valid_id?(value), do: Map.put(acc, :id, value), else: acc

        # No need for guard since valid_target? handles types
        :target ->
          if valid_target?(value), do: Map.put(acc, :target, value), else: acc

        :avatar when is_binary(value) ->
          Map.put(acc, :avatar, OpLinkSanitizer.sanitize(value, sanitize_options))

        :"end-point" when is_binary(value) ->
          Map.put(acc, :"end-point", OpLinkSanitizer.sanitize(value, sanitize_options))

        :slug when is_binary(value) ->
          Map.put(acc, :slug, value)

        _ ->
          acc
      end
    end)
  end

  def sanitize(_, _), do: %{}

  defp valid_class?(class_attr), do: Regex.match?(~r/^[a-zA-Z0-9_\-]{1,500}$/i, class_attr) != nil
  defp valid_id?(id_attr), do: Regex.match?(~r/^[a-zA-Z0-9_\-\:\.]{1,500}$/i, id_attr) != nil
  defp valid_target?(target), do: target in ["_self", "_blank", "_parent", "_top"]
end

defmodule QuillDeltaToHtml.ValueTypes do
  import EctoEnum

  defenum(ListType,
    ordered: "ordered",
    bullet: "bullet",
    checked: "checked",
    unchecked: "unchecked"
  )

  defenum(ScriptType, sub: "sub", super: "super")
  defenum(DirectionType, rtl: "rtl")
  defenum(AlignType, left: "left", center: "center", right: "right", justify: "justify")
  defenum(DataType, image: "image", video: "video", formula: "formula", text: "text")

  defenum(GroupType,
    block: "block",
    "inline-group": "inline-group",
    list: "list",
    video: "video",
    table: "table"
  )

  def new_line, do: "\n"
end

defmodule QuillDeltaToHtml do
  alias QuillDeltaToHtml.QuillDeltaToHtmlConverter

  def convert(delta_ops, options \\ nil) do
    converter = QuillDeltaToHtmlConverter.new(delta_ops, options)
    QuillDeltaToHtmlConverter.convert(converter)
  end
end
