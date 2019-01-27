defmodule Wax.AttestationStatementFormat.Packed do
  require Logger

  @behaviour Wax.AttestationStatementFormat

  # from https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2#Officially_assigned_code_elements
  # on the 27/01/2019
  @iso_3166_codes [
    "AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR", "AS", "AT", "AU", "AW", "AX",
    "AZ", "BA", "BB", "BD", "BE", "BF", "BG", "BH", "BI", "BJ", "BL", "BM", "BN", "BO", "BQ",
    "BQ", "BR", "BS", "BT", "BV", "BW", "BY", "BZ", "CA", "CC", "CD", "CF", "CG", "CH", "CI",
    "CK", "CL", "CM", "CN", "CO", "CR", "CU", "CV", "CW", "CX", "CY", "CZ", "DE", "DJ", "DK",
    "DM", "DO", "DZ", "EC", "EE", "EG", "EH", "ER", "ES", "ET", "FI", "FJ", "FK", "FM", "FO",
    "FR", "GA", "GB", "GD", "GE", "GF", "GG", "GH", "GI", "GL", "GM", "GN", "GP", "GQ", "GR",
    "GS", "GT", "GU", "GW", "GY", "HK", "HM", "HN", "HR", "HT", "HU", "ID", "IE", "IL", "IM",
    "IN", "IO", "IQ", "IR", "IS", "IT", "JE", "JM", "JO", "JP", "KE", "KG", "KH", "KI", "KM",
    "KN", "KP", "KR", "KW", "KY", "KZ", "LA", "LB", "LC", "LI", "LK", "LR", "LS", "LT", "LU",
    "LV", "LY", "MA", "MC", "MD", "ME", "MF", "MG", "MH", "MK", "ML", "MM", "MN", "MO", "MP",
    "MQ", "MR", "MS", "MT", "MU", "MV", "MW", "MX", "MY", "MZ", "NA", "NC", "NE", "NF", "NG",
    "NI", "NL", "NO", "NP", "NR", "NU", "NZ", "OM", "PA", "PE", "PF", "PG", "PH", "PK", "PL",
    "PM", "PN", "PR", "PS", "PT", "PW", "PY", "QA", "RE", "RO", "RS", "RU", "RW", "SA", "SB",
    "SC", "SD", "SE", "SG", "SH", "SI", "SJ", "SK", "SL", "SM", "SN", "SO", "SR", "SS", "ST",
    "SV", "SX", "SY", "SZ", "TC", "TD", "TF", "TG", "TH", "TJ", "TK", "TL", "TM", "TN", "TO",
    "TR", "TT", "TV", "TW", "IS", "TZ", "UA", "UG", "UM", "US", "UY", "UZ", "VA", "VC", "VE",
    "VG", "VI", "VN", "VU", "WF", "WS", "YE", "YT", "ZA", "ZM", "ZW"
  ]

  @impl Wax.AttestationStatementFormat
  def verify(%{"x5c" => _} = att_stmt, auth_data, client_data_hash, auth_data_bin) do
    with :ok <- valid_cbor?(att_stmt),
         :ok <- valid_x5c_signature?(att_stmt, auth_data_bin, client_data_hash),
         :ok <- valid_attestation_certificate?(List.first(att_stmt["x5c"]), auth_data)
    do
      attestation_type = determine_attestation_type(auth_data)

      {:ok, {attestation_type, att_stmt["x5c"]}}
    else
      error ->
        error
    end
  end

  def verify(%{"ecdaaKeyId" => _}, _, _, _), do: {:error, :attestation_packed_unimplemented}

  # self-attestation case

  def verify(att_stmt, auth_data, client_data_hash, auth_data_bin) do
    with :ok <- valid_cbor?(att_stmt),
         :ok <- algs_match?(att_stmt, auth_data),
         :ok <- valid_self_signature?(att_stmt, auth_data, auth_data_bin, client_data_hash)
    do
      {:ok, {:self, nil}}
    else
      error ->
        error
    end
  end

  @spec valid_cbor?(Wax.Attestation.Statement.t()) :: :ok | {:error, any()}

  defp valid_cbor?(%{"x5c" => _} = att_stmt) do
    if is_integer(att_stmt["alg"])
    and is_binary(att_stmt["sig"])
    and is_list(att_stmt["x5c"])
    and length(Map.keys(att_stmt)) == 3
    do
      :ok
    else
      {:error, :attestation_packed_invalid_cbor}
    end
  end

  defp valid_cbor?(att_stmt) do
    if is_integer(att_stmt["alg"])
    and is_binary(att_stmt["sig"])
    and length(Map.keys(att_stmt)) == 2
    do
      :ok
    else
      {:error, :attestation_packed_invalid_cbor}
    end
  end

  @spec valid_x5c_signature?(map(), binary(), Wax.Client.hash()) :: :ok | {:error, any()}

  defp valid_x5c_signature?(att_stmt, auth_data_bin, client_data_hash) do
    #FIXME: check if the "alg" matches the certificate's public key?

    pub_key = 
      att_stmt["x5c"]
      |> List.first()
      |> X509.Certificate.from_der!()
      |> X509.Certificate.public_key()

    digest = Wax.CoseKey.to_erlang_digest(%{3 => att_stmt["alg"]})

    if :public_key.verify(auth_data_bin <> client_data_hash, digest, att_stmt["sig"], pub_key) do
      :ok
    else
      {:error, :attestation_packed_invalid_signature}
    end
  end

  @spec valid_self_signature?(map(), Wax.AuthenticatorData.t(), binary(), Wax.Client.hash())
    :: :ok | {:error, any()}

  defp valid_self_signature?(att_stmt, auth_data, auth_data_bin, client_data_hash) do
    pub_key =
      Wax.CoseKey.to_erlang_public_key(auth_data.attested_credential_data.credential_public_key)

    digest = Wax.CoseKey.to_erlang_digest(%{3 => att_stmt["alg"]})

    if :public_key.verify(auth_data_bin <> client_data_hash, digest, att_stmt["sig"], pub_key) do
      :ok
    else
      {:error, :attestation_packed_invalid_signature}
    end
  end

  @spec algs_match?(map(), Wax.AuthenticatorData.t()) :: :ok | {:error, any()}

  defp algs_match?(att_stmt, auth_data) do
    if att_stmt["alg"] == auth_data.attested_credential_data.credential_public_key[3] do
      :ok
    else
      {:attestation_packed_algs_mismatch}
    end
  end

  @spec valid_attestation_certificate?(binary(), Wax.AuthenticatorData.t())
    :: :ok | {:error, any()}

  defp valid_attestation_certificate?(cert_der, auth_data) do
    cert = X509.Certificate.from_der!(cert_der)

    if Wax.Utils.Certificate.version(cert) == :v3
      and Wax.Utils.Certificate.subject_component_value(cert, "C") in @iso_3166_codes
      and Wax.Utils.Certificate.subject_component_value(cert, "O") not in [nil, ""]
      and Wax.Utils.Certificate.subject_component_value(cert, "OU") == "Authenticator Attestation"
      and Wax.Utils.Certificate.subject_component_value(cert, "CN") not in [nil, ""]
      and Wax.Utils.Certificate.basic_constraints_ext_ca_component(cert) == false
    do
      # checking if oid of id-fido-gen-ce-aaguid is present and, if so, aaguid
      case X509.Certificate.extension(cert, {1, 3, 6, 1, 4, 1, 45724, 1, 1, 4}) do
        {:Extension, {1, 3, 6, 1, 4, 1, 45724, 1, 1, 4}, _, aaguid} ->
          if aaguid == auth_data.attested_credential_data.aaguid do
            :ok
          else
            {:error, :attestation_packed_invalid_attestation_cert}
          end

        nil ->
          :ok
      end
    else
      {:error, :attestation_packed_invalid_attestation_cert}
    end
  end

  @spec determine_attestation_type(Wax.AuthenticatorData.t()) :: Wax.Attestation.type()

  defp determine_attestation_type(auth_data) do
    case Wax.Metadata.get_by_aaguid(auth_data.attested_credential_data.aaguid) do
      nil ->
        :uncertain

      #FIXME: here we assume that :basic and :attca are exclusive for a given authenticator
      # but this seems however unspecified
      metadata_statement ->
        if :tag_attestation_basic_full in metadata_statement.attestation_types do
          :basic
        else
          if :tag_attestation_attca in metadata_statement.attestation_types do
            :attca
          else
            :uncertain
          end
        end
    end
  end
end
