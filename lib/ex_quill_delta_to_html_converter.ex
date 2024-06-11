defmodule ExQuillDeltaToHtmlConverter do
  defmodule Helpers do
    defmodule Object do
      def assign(target, sources) do
        Enum.reduce(sources, target, fn source, acc ->
          Map.merge(acc, source)
        end)
      end
    end

    defmodule Array do
      def find(arr, predicate) do
        Enum.find(arr, predicate)
      end

      def group_consecutive_elements_while(arr, predicate) do
        arr
        |> Enum.chunk_while([], fn curr, acc ->
          if acc == [] or predicate.(curr, List.last(acc)) do
            {:cont, [curr | acc]}
          else
            {:cont, acc, [curr]}
          end
        end, fn
          [] -> {:cont, []}
          acc -> {:cont, acc, []}
        end)
        |> Enum.map(fn group ->
          if length(group) == 1, do: hd(group), else: Enum.reverse(group)
        end)
      end

      def flatten(arr) do
        Enum.flat_map(arr, fn
          list when is_list(list) -> flatten(list)
          item -> [item]
        end)
      end
    end

    defmodule StringHelper do
      def tokenize_with_new_lines(str) do
        str
        |> String.split(~r/\n/)
        |> Enum.map(fn line ->
          if line == "", do: "\n", else: line
        end)
      end
    end
  end

  defmodule ValueTypes do
    @new_line "\n"
    @list_types [:ordered, :bullet, :checked, :unchecked]
    @script_types [:sub, :super]
    @direction_types [:rtl]
    @align_types [:left, :center, :right, :justify]
    @data_types [:image, :video, :formula, :text]
    @group_types [:block, :inline_group, :list, :video, :table]

    def new_line, do: @new_line
    def list_types, do: @list_types
    def script_types, do: @script_types
    def direction_types, do: @direction_types
    def align_types, do: @align_types
    def data_types, do: @data_types
    def group_types, do: @group_types
  end

  defmodule InsertData do
    defstruct [:type, :value]
  end

  defmodule OpAttributeSanitizer do
    def sanitize(nil, _options), do: %{}

    def sanitize(attrs, _options) do
      attrs
      |> Enum.filter(fn {key, _} ->
        key in [
          "bold",
          "italic",
          "underline",
          "strike",
          "code",
          "color",
          "background",
          "font",
          "size",
          "link",
          "script",
          "list",
          "header",
          "align",
          "direction",
          "indent",
          "mentions",
          "mention",
          "width",
          "target",
          "rel"
        ]
      end)
      |> Enum.into(%{})
    end
  end

  defmodule DeltaInsertOp do
    defstruct [:insert, :attributes]

    def create_new_line_op do
      %__MODULE__{insert: ValueTypes.new_line()}
    end

    def video?(%__MODULE__{insert: %{video: _}}), do: true
    def video?(_), do: false

    def container_block?(%__MODULE__{attributes: %{blockquote: _}}), do: true
    def container_block?(%__MODULE__{attributes: %{code_block: _}}), do: true
    def container_block?(%__MODULE__{attributes: %{list: _}}), do: true
    def container_block?(%__MODULE__{attributes: %{header: _}}), do: true
    def container_block?(_), do: false

    def can_be_in_block?(%__MODULE__{insert: %{image: _}}), do: false
    def can_be_in_block?(%__MODULE__{insert: %{video: _}}), do: false
    def can_be_in_block?(%__MODULE__{insert: "\n"}), do: false
    def can_be_in_block?(_), do: true

    def inline?(%__MODULE__{insert: %{image: _}}), do: false
    def inline?(%__MODULE__{insert: %{video: _}}), do: false
    def inline?(_), do: true
  end

  defmodule InsertOpDenormalizer do
    def denormalize(op) when is_map(op) do
      op.insert
      |> ExQuillDeltaToHtmlConverter.Helpers.StringHelper.tokenize_with_new_lines()
      |> Enum.map(fn line ->
        if line == ValueTypes.new_line() do
          Map.put(op, :insert, line)
        else
          Map.put(op, :insert, line)
        end
      end)
    end

    def denormalize(_op), do: []
  end

  defmodule GroupTypes do
    defmodule BlockGroup do
      defstruct [:op, :ops]

      def new(op, ops \\ []) do
        %__MODULE__{op: op, ops: ops}
      end

      def same_style?(%__MODULE__{op: op1}, %__MODULE__{op: op2}) do
        op1.attributes == op2.attributes
      end
    end

    defmodule InlineGroup do
      defstruct [:ops]

      def new(ops) do
        %__MODULE__{ops: ops}
      end
    end

    defmodule ListGroup do
      defstruct [:items]

      def new(items) do
        %__MODULE__{items: items}
      end
    end

    defmodule ListItem do
      defstruct [:item, :inner_list]

      def new(item, inner_list \\ nil) do
        %__MODULE__{item: item, inner_list: inner_list}
      end
    end

    defmodule VideoItem do
      defstruct [:op]

      def new(op) do
        %__MODULE__{op: op}
      end
    end
  end

  defmodule Grouper do
    alias ExQuillDeltaToHtmlConverter.{DeltaInsertOp, Helpers}
    alias ExQuillDeltaToHtmlConverter.GroupTypes.{BlockGroup, InlineGroup, VideoItem}

    def group(ops) do
      ops
      |> pair_ops_with_their_block()
      |> group_consecutive_same_style_blocks()
      |> reduce_consecutive_same_style_blocks_to_one()
    end

    defp pair_ops_with_their_block(ops) do
      Enum.reduce(ops, [], fn op, acc ->
        cond do
          DeltaInsertOp.video?(op) ->
            [VideoItem.new(op) | acc]

          DeltaInsertOp.container_block?(op) ->
            block_ops = Enum.take_while(acc, &DeltaInsertOp.can_be_in_block?/1)
            [BlockGroup.new(op, Enum.reverse(block_ops)) | acc -- block_ops]

          true ->
            inline_ops = Enum.take_while(acc, &DeltaInsertOp.inline?/1)
            [InlineGroup.new([op | Enum.reverse(inline_ops)]) | acc -- inline_ops]
        end
      end)
      |> Enum.reverse()
    end

    defp group_consecutive_same_style_blocks(groups) do
      Helpers.Array.group_consecutive_elements_while(groups, fn g1, g2 ->
        BlockGroup.same_style?(g1, g2)
      end)
    end

    defp reduce_consecutive_same_style_blocks_to_one(groups) do
      Enum.map(groups, fn group ->
        case group do
          [block_group | _] = same_style_groups ->
            blocks =
              same_style_groups
              |> Enum.flat_map(& &1.ops)
              |> Enum.intersperse(DeltaInsertOp.create_new_line_op())

            BlockGroup.new(block_group.op, blocks)

          single_group ->
            single_group
        end
      end)
    end
  end

  defmodule ListNester do
    alias ExQuillDeltaToHtmlConverter.{DeltaInsertOp, Grouper, GroupTypes}
    alias ExQuillDeltaToHtmlConverter.Helpers.Array

    def nest(groups) do
      groups
      |> convert_list_blocks_to_list_groups()
      |> group_consecutive_list_groups()
      |> Enum.map(&nest_list_section/1)
      |> Array.flatten()
    end

    defp convert_list_blocks_to_list_groups(groups) do
      Enum.map(groups, fn group ->
        case group do
          %GroupTypes.BlockGroup{op: %{insert: %{list: _}}} = block_group ->
            GroupTypes.ListGroup.new([GroupTypes.ListItem.new(block_group)])

          _other ->
            group
        end
      end)
    end


    defp group_consecutive_list_groups(groups) do
      Enum.chunk_while(groups, [], fn
        %GroupTypes.ListGroup{} = group, [] ->
          {:cont, [group]}

        %GroupTypes.ListGroup{} = group, acc ->
          {:cont, [group | acc]}

        group, acc ->
          {:cont, acc, [group]}
      end, fn
        [] -> {:cont, []}
        acc -> {:cont, acc, []}
      end)
      |> Enum.map(&Enum.reverse/1)
    end

    defp nest_list_section([%GroupTypes.ListGroup{} = group]), do: group

    defp nest_list_section(groups) do
      Enum.reduce(Enum.reverse(groups), [], fn group, acc ->
        case place_under_parent(group, acc) do
          {true, updated_acc} ->
            updated_acc

          {false, _} ->
            [group | acc]
        end
      end)
    end

    defp place_under_parent(group, groups) do
      Enum.reduce_while(Enum.with_index(groups), {false, groups}, fn {parent_group, index},
                                                                     {_, acc} ->
        first_item = hd(group.items)
        parent_item = List.last(parent_group.items)

        if first_item.item.op.indent > parent_item.item.op.indent do
          updated_parent_item =
            parent_item
            |> Map.update(:inner_list, group, fn inner_list ->
              GroupTypes.ListGroup.new(inner_list.items ++ group.items)
            end)

          updated_parent_group = put_in(parent_group.items, -1, updated_parent_item)
          updated_acc = List.replace_at(acc, index, updated_parent_group)
          {:halt, {true, updated_acc}}
        else
          {:cont, {false, acc}}
        end
      end)
    end
  end

  defmodule OpToHtmlConverter do
    alias ExQuillDeltaToHtmlConverter.{DeltaInsertOp, InsertData, OpAttributeSanitizer, GroupTypes}

    def convert(%DeltaInsertOp{insert: %InsertData{type: type, value: value}, attributes: attrs}) do
      attrs = OpAttributeSanitizer.sanitize(attrs, [])
      converter_fn = converter(type)
      converter_fn.(value, attrs)
    end

    def convert(%GroupTypes.InlineGroup{ops: ops}) do
      ops
      |> Enum.map(&convert/1)
      |> Enum.join("")
    end

    defp converter(:image), do: &image_to_html/2
    defp converter(:text), do: &text_to_html/2
    defp converter(:video), do: &video_to_html/2
    defp converter(_), do: fn _value, _attrs -> "" end

    defp image_to_html(value, attrs) do
      img_tag_attrs =
        attrs
        |> Map.put("src", value)
        |> Enum.map(fn {k, v} -> "#{k}=\"#{v}\"" end)
        |> Enum.join(" ")

      "<img #{img_tag_attrs}/>"
    end

    defp text_to_html(value, attrs) do
      tag = if Map.get(attrs, "link"), do: "a", else: "span"

      tag_attrs =
        attrs
        |> Enum.map(fn {k, v} -> "#{k}=\"#{v}\"" end)
        |> Enum.join(" ")

      "<#{tag}#{tag_attrs}>#{value}</#{tag}>"
    end

    defp video_to_html(value, attrs) do
      video_tag_attrs =
        attrs
        |> Map.put("src", value)
        |> Enum.map(fn {k, v} -> "#{k}=\"#{v}\"" end)
        |> Enum.join(" ")

      "<iframe #{video_tag_attrs}></iframe>"
    end
  end

  def convert(ops, options \\ []) do
    grouped_ops = Grouper.group(ops)
    nested_groups = ListNester.nest(grouped_ops)

    html =
      Enum.map(nested_groups, fn group ->
        OpToHtmlConverter.convert(group)
      end)
      |> Enum.join("")

    if options[:encode_html] do
      HtmlEntities.encode(html)
    else
      html
    end
  end
end
