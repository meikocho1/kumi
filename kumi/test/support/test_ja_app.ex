defmodule Kumi.Test.JaApp do
  @moduledoc """
  A `Kumi.App` fixture declared in Japanese — the same shape as
  `Kumi.Test.App` plus `locale :ja` and a label for every kind of thing
  `admin.labels` accepts (a resource, one of its attributes, a workflow,
  one of its stages, a dashboard, one of its metrics).

  Kept separate from `Kumi.Test.App` so the English default keeps being
  exercised by everything that already uses that one.
  """

  use Kumi.App

  app do
    name :ja_app
    title("ためしアプリ")
    locale(:ja)
  end

  resources do
    resource Kumi.Test.Account
  end

  admin do
    navigation([Kumi.Test.Account])

    labels(%{
      Kumi.Test.Account => "取引先",
      {Kumi.Test.Account, :industry} => "業種",
      :onboarding => "オンボーディング",
      {:onboarding, :invited} => "招待済み",
      :overview => "概要",
      {:overview, :account_count} => "取引先数"
    })
  end

  workflow(:onboarding,
    resource: Kumi.Test.Account,
    field: :industry,
    stages: [:invited, :active]
  )

  dashboard :overview do
    metric(:account_count, resource: Kumi.Test.Account)
  end
end
