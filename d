import pandas as pd
import numpy as np
import xlsxwriter

# ---------------------------------------------------------------
# National sales analysis by period
# input : df with 10 cols from the sales extract
# output: analytical workbook, no raw data dump
# ---------------------------------------------------------------

OUT = "National_Sales_Analysis.xlsx"

TXT = ["ARTCL_NUM", "SCAN_CD", "STR_SITE_NUM", "TERR_CD", "INDST_KEY_NUM"]
NUM = ["SL_AMT", "SL_QTY"]


# ---------- 1. clean ----------

def clean(df):
    d = df.copy()
    n0 = len(d)

    for c in TXT:
        d[c] = d[c].astype(str).str.strip()

    for c in NUM:
        d[c] = pd.to_numeric(d[c], errors="coerce")

    bad = d[NUM].isna().any(axis=1).sum()
    print("rows in:", n0, "| unparsed measure rows:", bad)
    if bad:
        print(d[d[NUM].isna().any(axis=1)].head())
        raise ValueError("SL_AMT/SL_QTY failed to convert, inspect above before continuing")

    d["PKEY"] = (d.Corporate_Year_Num.astype(str) + "-P"
                 + d.Period_Num.astype(str).str.zfill(2))
    d["PIDX"] = d.Corporate_Year_Num * 13 + d.Period_Num

    print("periods:", d.PKEY.nunique(), "| range:", d.PKEY.min(), "->", d.PKEY.max())
    print("articles:", d.ARTCL_NUM.nunique(), "| terr:", d.TERR_CD.nunique(),
          "| stores:", d.STR_SITE_NUM.nunique())
    print("negatives:", (d.SL_AMT < 0).sum(), "| zero amt:", (d.SL_AMT == 0).sum())
    return d


# ---------- 2. base table ----------

def make_base(d):
    g = ["Corporate_Year_Num", "Quarter_Num", "Period_Num", "PKEY", "PIDX",
         "TERR_CD", "ARTCL_NUM", "INDST_KEY_NUM"]
    b = d.groupby(g, as_index=False)[NUM].sum()

    diff = round(b.SL_AMT.sum() - d.SL_AMT.sum(), 2)
    print("base rows:", len(b), "| tie-out diff:", diff)
    if abs(diff) > 0.01:
        raise ValueError("base table does not tie to source")
    return b


# ---------- 3. helpers ----------

def add_kpis(t):
    t["AVG_PRICE"] = np.where(t.SL_QTY != 0, t.SL_AMT / t.SL_QTY, np.nan)
    return t


def comparable_yoy(t, ycol, pcol, val):
    # compares each year to prior year on periods present in BOTH years
    out = []
    yrs = sorted(t[ycol].unique())
    for i in range(1, len(yrs)):
        cy, py = yrs[i], yrs[i - 1]
        cp = set(t.loc[t[ycol] == cy, pcol])
        pp = set(t.loc[t[ycol] == py, pcol])
        both = sorted(cp & pp)
        if not both:
            continue
        c = t[(t[ycol] == cy) & (t[pcol].isin(both))][val].sum()
        p = t[(t[ycol] == py) & (t[pcol].isin(both))][val].sum()
        out.append({"Year": cy, "Prior_Year": py, "Periods_Compared": len(both),
                    "Period_List": "P" + str(min(both)) + "-P" + str(max(both)),
                    "Curr": c, "Prior": p,
                    "Var": c - p, "Var_Pct": (c - p) / p if p else np.nan})
    return pd.DataFrame(out)


# ---------- 4. sheet builders ----------

def sheet_period(b, d):
    t = b.groupby(["Corporate_Year_Num", "Quarter_Num", "Period_Num", "PKEY", "PIDX"],
                  as_index=False)[NUM].sum()

    st = d.groupby("PKEY").STR_SITE_NUM.nunique().rename("STORES")
    ar = d.groupby("PKEY").ARTCL_NUM.nunique().rename("ARTICLES")
    t = t.merge(st, on="PKEY").merge(ar, on="PKEY").sort_values("PIDX")

    t = add_kpis(t)
    t["SALES_PER_STORE"] = t.SL_AMT / t.STORES
    t["POP_PCT"] = t.SL_AMT.pct_change()

    # yoy = same period prior year, only where it exists
    m = t.set_index("PIDX").SL_AMT
    t["LY_AMT"] = t.PIDX.sub(13).map(m)
    t["YOY_PCT"] = np.where(t.LY_AMT.notna() & (t.LY_AMT != 0),
                            (t.SL_AMT - t.LY_AMT) / t.LY_AMT, np.nan)
    t["SHARE_OF_TOTAL"] = t.SL_AMT / t.SL_AMT.sum()

    cols = ["PKEY", "Corporate_Year_Num", "Quarter_Num", "Period_Num", "SL_AMT", "SL_QTY",
            "AVG_PRICE", "STORES", "ARTICLES", "SALES_PER_STORE",
            "POP_PCT", "LY_AMT", "YOY_PCT", "SHARE_OF_TOTAL"]
    return t[cols].reset_index(drop=True)


def sheet_year(b, d):
    t = b.groupby("Corporate_Year_Num", as_index=False)[NUM].sum()
    p = b.groupby("Corporate_Year_Num").Period_Num.nunique().rename("PERIODS")
    st = d.groupby("Corporate_Year_Num").STR_SITE_NUM.nunique().rename("STORES_ACTIVE")
    t = t.merge(p, on="Corporate_Year_Num").merge(st, on="Corporate_Year_Num")

    t = add_kpis(t)
    t["AMT_PER_PERIOD"] = t.SL_AMT / t.PERIODS
    t["COMPLETE"] = np.where(t.PERIODS == 13, "Yes", "No - partial")
    return t


def sheet_terr(b, d):
    t = b.groupby(["TERR_CD", "Corporate_Year_Num"], as_index=False)[NUM].sum()
    w = t.pivot(index="TERR_CD", columns="Corporate_Year_Num", values="SL_AMT").fillna(0)
    w.columns = ["FY" + str(c) for c in w.columns]

    tot = b.groupby("TERR_CD")[NUM].sum()
    st = d.groupby("TERR_CD").STR_SITE_NUM.nunique().rename("STORES")

    w = w.join(tot).join(st)
    w["SHARE"] = w.SL_AMT / w.SL_AMT.sum()
    w["AMT_PER_STORE"] = w.SL_AMT / w.STORES
    w["AVG_PRICE"] = np.where(w.SL_QTY != 0, w.SL_AMT / w.SL_QTY, np.nan)

    # comparable yoy per territory, latest year vs prior
    yrs = sorted(b.Corporate_Year_Num.unique())
    cy, py = yrs[-1], yrs[-2]
    both = sorted(set(b.loc[b.Corporate_Year_Num == cy, "Period_Num"]) &
                  set(b.loc[b.Corporate_Year_Num == py, "Period_Num"]))
    sub = b[b.Period_Num.isin(both)]
    cc = sub[sub.Corporate_Year_Num == cy].groupby("TERR_CD").SL_AMT.sum()
    pp = sub[sub.Corporate_Year_Num == py].groupby("TERR_CD").SL_AMT.sum()
    w["YOY_COMP_PCT"] = ((cc - pp) / pp).reindex(w.index)

    return w.sort_values("SL_AMT", ascending=False).reset_index()


def sheet_article(b):
    yrs = sorted(b.Corporate_Year_Num.unique())
    cy, py = yrs[-1], yrs[-2]
    both = sorted(set(b.loc[b.Corporate_Year_Num == cy, "Period_Num"]) &
                  set(b.loc[b.Corporate_Year_Num == py, "Period_Num"]))

    t = b.groupby(["ARTCL_NUM", "INDST_KEY_NUM"], as_index=False)[NUM].sum()
    t = add_kpis(t)
    t["SHARE"] = t.SL_AMT / t.SL_AMT.sum()
    t = t.sort_values("SL_AMT", ascending=False).reset_index(drop=True)
    t["RANK"] = t.index + 1
    t["CUM_SHARE"] = t.SHARE.cumsum()

    ap = b.groupby("ARTCL_NUM").PKEY.nunique().rename("PERIODS_ACTIVE")
    t = t.merge(ap, on="ARTCL_NUM")

    sub = b[b.Period_Num.isin(both)]
    cc = sub[sub.Corporate_Year_Num == cy].groupby("ARTCL_NUM").SL_AMT.sum()
    pp = sub[sub.Corporate_Year_Num == py].groupby("ARTCL_NUM").SL_AMT.sum()
    cmp_df = pd.concat([cc.rename("CURR"), pp.rename("PRIOR")], axis=1).fillna(0)
    cmp_df["VAR"] = cmp_df.CURR - cmp_df.PRIOR
    cmp_df["VAR_PCT"] = np.where(cmp_df.PRIOR != 0,
                                 cmp_df.VAR / cmp_df.PRIOR, np.nan)
    t = t.merge(cmp_df, on="ARTCL_NUM", how="left")

    cols = ["RANK", "ARTCL_NUM", "INDST_KEY_NUM", "SL_AMT", "SL_QTY", "AVG_PRICE",
            "SHARE", "CUM_SHARE", "PERIODS_ACTIVE", "CURR", "PRIOR", "VAR", "VAR_PCT"]
    return t[cols], cy, py, both


def sheet_movers(art, n=15):
    a = art[art.PRIOR.notna() & (art.PRIOR != 0)].copy()
    up = a.nlargest(n, "VAR")
    dn = a.nsmallest(n, "VAR")
    up.insert(0, "DIRECTION", "Gainer")
    dn.insert(0, "DIRECTION", "Decliner")
    c = ["DIRECTION", "ARTCL_NUM", "INDST_KEY_NUM", "CURR", "PRIOR", "VAR", "VAR_PCT"]
    return pd.concat([up[c], dn[c]], ignore_index=True)


def sheet_industry(b):
    t = b.groupby(["INDST_KEY_NUM", "Corporate_Year_Num"], as_index=False)[NUM].sum()
    w = t.pivot(index="INDST_KEY_NUM", columns="Corporate_Year_Num",
                values="SL_AMT").fillna(0)
    w.columns = ["FY" + str(c) for c in w.columns]

    tot = b.groupby("INDST_KEY_NUM")[NUM].sum()
    na = b.groupby("INDST_KEY_NUM").ARTCL_NUM.nunique().rename("ARTICLES")
    w = w.join(tot).join(na)
    w["SHARE"] = w.SL_AMT / w.SL_AMT.sum()
    w["AVG_PRICE"] = np.where(w.SL_QTY != 0, w.SL_AMT / w.SL_QTY, np.nan)
    return w.sort_values("SL_AMT", ascending=False).reset_index()


def sheet_qtr(b):
    t = b.groupby(["Corporate_Year_Num", "Quarter_Num"], as_index=False)[NUM].sum()
    t["PKEY"] = t.Corporate_Year_Num.astype(str) + "-Q" + t.Quarter_Num.astype(str)
    np_ = b.groupby(["Corporate_Year_Num", "Quarter_Num"]).Period_Num.nunique()
    t = t.merge(np_.rename("PERIODS"), on=["Corporate_Year_Num", "Quarter_Num"])
    t = add_kpis(t)
    t["AMT_PER_PERIOD"] = t.SL_AMT / t.PERIODS
    return t[["PKEY", "Corporate_Year_Num", "Quarter_Num", "PERIODS",
              "SL_AMT", "SL_QTY", "AVG_PRICE", "AMT_PER_PERIOD"]]


# ---------- 5. formatting ----------

def build_formats(wb):
    f = {}
    f["title"] = wb.add_format({"font_name": "Arial", "font_size": 14, "bold": True,
                                "font_color": "#1F3864"})
    f["sub"] = wb.add_format({"font_name": "Arial", "font_size": 9,
                              "font_color": "#595959", "italic": True})
    f["hdr"] = wb.add_format({"font_name": "Arial", "font_size": 10, "bold": True,
                              "bg_color": "#1F3864", "font_color": "white",
                              "border": 1, "text_wrap": True, "valign": "vcenter",
                              "align": "center"})
    f["txt"] = wb.add_format({"font_name": "Arial", "font_size": 10})
    f["amt"] = wb.add_format({"font_name": "Arial", "font_size": 10,
                              "num_format": "#,##0.00;(#,##0.00);-"})
    f["qty"] = wb.add_format({"font_name": "Arial", "font_size": 10,
                              "num_format": "#,##0;(#,##0);-"})
    f["pct"] = wb.add_format({"font_name": "Arial", "font_size": 10,
                              "num_format": "0.0%;(0.0%);-"})
    f["prc"] = wb.add_format({"font_name": "Arial", "font_size": 10,
                              "num_format": "#,##0.00"})
    f["tot"] = wb.add_format({"font_name": "Arial", "font_size": 10, "bold": True,
                              "top": 2, "num_format": "#,##0.00;(#,##0.00);-"})
    f["totq"] = wb.add_format({"font_name": "Arial", "font_size": 10, "bold": True,
                               "top": 2, "num_format": "#,##0;(#,##0);-"})
    f["totl"] = wb.add_format({"font_name": "Arial", "font_size": 10, "bold": True,
                               "top": 2})
    f["note"] = wb.add_format({"font_name": "Arial", "font_size": 10, "text_wrap": True,
                               "valign": "top"})
    f["nb"] = wb.add_format({"font_name": "Arial", "font_size": 10, "bold": True})
    f["kpi_l"] = wb.add_format({"font_name": "Arial", "font_size": 10, "bold": True,
                                "bg_color": "#D9E2F3", "border": 1})
    f["kpi_v"] = wb.add_format({"font_name": "Arial", "font_size": 12, "border": 1,
                                "num_format": "#,##0.00", "align": "right"})
    f["kpi_t"] = wb.add_format({"font_name": "Arial", "font_size": 12, "border": 1,
                                "align": "right"})
    return f


def pick_fmt(col, f):
    c = col.upper()
    if "PCT" in c or "SHARE" in c:
        return f["pct"], 11
    if "PRICE" in c or "PER_STORE" in c or "PER_PERIOD" in c:
        return f["prc"], 13
    if "AMT" in c or c in ("CURR", "PRIOR", "VAR") or c.startswith("FY"):
        return f["amt"], 15
    if "QTY" in c or c in ("STORES", "ARTICLES", "PERIODS", "RANK",
                           "PERIODS_ACTIVE", "STORES_ACTIVE", "PERIODS_COMPARED"):
        return f["qty"], 11
    return f["txt"], 14


def write_sheet(wb, name, title, note, t, f, total_cols=(), freeze="A5"):
    ws = wb.add_worksheet(name)
    ws.hide_gridlines(2)
    ws.write("A1", title, f["title"])
    ws.write("A2", note, f["sub"])

    r0 = 3
    for j, c in enumerate(t.columns):
        ws.write(r0, j, c, f["hdr"])
        fmt, w = pick_fmt(c, f)
        ws.set_column(j, j, w, fmt)
    ws.set_row(r0, 30)

    for i, row in enumerate(t.itertuples(index=False), start=r0 + 1):
        for j, v in enumerate(row):
            if pd.isna(v):
                ws.write_blank(i, j, None)
            else:
                ws.write(i, j, v)

    last = r0 + len(t)
    if total_cols:
        ws.write(last + 1, 0, "TOTAL", f["totl"])
        for c in total_cols:
            j = t.columns.get_loc(c)
            col = xlsxwriter.utility.xl_col_to_name(j)
            tf = f["totq"] if "QTY" in c.upper() else f["tot"]
            ws.write_formula(last + 1, j,
                             "=SUM({0}{1}:{0}{2})".format(col, r0 + 2, last + 1), tf)

    ws.freeze_panes(freeze)
    ws.autofilter(r0, 0, last, len(t.columns) - 1)
    return ws, r0, last


# ---------- 6. main ----------

def run(df, out=OUT):
    d = clean(df)
    b = make_base(d)

    per = sheet_period(b, d)
    yr = sheet_year(b, d)
    qtr = sheet_qtr(b)
    ter = sheet_terr(b, d)
    art, cy, py, both = sheet_article(b)
    mov = sheet_movers(art)
    ind = sheet_industry(b)
    yoy = comparable_yoy(b, "Corporate_Year_Num", "Period_Num", "SL_AMT")

    span = per.PKEY.iloc[0] + " to " + per.PKEY.iloc[-1]
    tot_amt = per.SL_AMT.sum()
    tot_qty = per.SL_QTY.sum()

    wb = xlsxwriter.Workbook(out, {"nan_inf_to_errors": True})
    f = build_formats(wb)

    # --- notes ---
    ws = wb.add_worksheet("Read Me")
    ws.hide_gridlines(2)
    ws.set_column(0, 0, 26)
    ws.set_column(1, 1, 95)
    ws.write("A1", "National Sales Analysis", f["title"])
    ws.write("A2", "Scope, method and caveats. Read before using the numbers.", f["sub"])
    lastp = per[per.Corporate_Year_Num == cy].Period_Num.max()
    notes = [
        ("Request", "Total national sales for the supplied article list, broken down by fiscal period."),
        ("Coverage", "Fiscal periods " + span + ". " + str(per.PKEY.nunique())
         + " periods, 13-period fiscal calendar."),
        ("FY2021 / FY2022", "NOT AVAILABLE in the source extract. The data begins at "
         + per.PKEY.iloc[0] + ". Any reference to FY2021 in the original request cannot be met "
         "from this dataset."),
        ("Partial years", "FY" + str(per.Corporate_Year_Num.iloc[0]) + " contains only period "
         + str(per.Period_Num.iloc[0]) + ". FY" + str(cy) + " runs to P"
         + str(lastp) + " and is incomplete. Full-year totals for these two years are NOT "
         "comparable to complete years."),
        ("Year-over-year method", "All YoY figures compare like periods only. FY" + str(cy)
         + " vs FY" + str(py) + " is restricted to P" + str(min(both)) + "-P" + str(max(both))
         + ", present in both years. Raw full-year differences are not used."),
        ("Grain", "Source rows aggregated to year / period / territory / article / industry. "
         "Store and scan code are rolled up. Sales amount ties to source exactly."),
        ("Store counts", "Distinct STR_SITE_NUM per period. Store network grows across the window, "
         "so total sales growth is partly network expansion. Sales per store is provided "
         "alongside every headline figure for this reason."),
        ("Negatives", "Negative sales amounts are retained. They represent returns and voids and "
         "are part of net sales. They are not filtered out."),
        ("National definition", "All " + str(ter.TERR_CD.nunique())
         + " territory codes included, no exclusions applied."),
        ("Articles", str(art.ARTCL_NUM.nunique()) + " distinct articles with recorded sales. "
         "Articles requested but never sold do not appear in the source and are absent here."),
        ("Source rows", "{:,}".format(len(df)) + " raw rows aggregated to {:,}".format(len(b))
         + " analytical rows."),
    ]
    r = 3
    for k, v in notes:
        ws.write(r, 0, k, f["nb"])
        ws.write(r, 1, v, f["note"])
        ws.set_row(r, 30)
        r += 1

    # --- exec summary ---
    ws = wb.add_worksheet("Exec Summary")
    ws.hide_gridlines(2)
    ws.set_column(0, 0, 34)
    ws.set_column(1, 1, 22)
    ws.write("A1", "Executive Summary", f["title"])
    ws.write("A2", "Fiscal periods " + span, f["sub"])

    yoy_last = yoy.iloc[-1] if len(yoy) else None
    top5 = art.head(5).SHARE.sum()
    n80 = int((art.CUM_SHARE <= 0.8).sum()) + 1

    kpis = [
        ("Total sales amount", tot_amt, "amt"),
        ("Total units", tot_qty, "qty"),
        ("Average selling price", tot_amt / tot_qty if tot_qty else np.nan, "prc"),
        ("Periods covered", per.PKEY.nunique(), "qty"),
        ("Distinct articles", art.ARTCL_NUM.nunique(), "qty"),
        ("Territories", ter.TERR_CD.nunique(), "qty"),
        ("Peak period", per.loc[per.SL_AMT.idxmax(), "PKEY"], "txt"),
        ("Peak period sales", per.SL_AMT.max(), "amt"),
        ("Lowest period", per.loc[per.SL_AMT.idxmin(), "PKEY"], "txt"),
        ("Lowest period sales", per.SL_AMT.min(), "amt"),
        ("Top territory", ter.TERR_CD.iloc[0], "txt"),
        ("Top territory share", ter.SHARE.iloc[0], "pct"),
        ("Top 5 articles, share of sales", top5, "pct"),
        ("Articles making 80% of sales", n80, "qty"),
    ]
    if yoy_last is not None:
        kpis += [
            ("FY" + str(int(yoy_last.Year)) + " vs FY" + str(int(yoy_last.Prior_Year))
             + " (" + yoy_last.Period_List + ")", yoy_last.Var_Pct, "pct"),
            ("  variance amount", yoy_last.Var, "amt"),
        ]

    r = 3
    for label, val, kind in kpis:
        ws.write(r, 0, label, f["kpi_l"])
        if kind == "txt":
            ws.write(r, 1, val, f["kpi_t"])
        else:
            fmt = wb.add_format({"font_name": "Arial", "font_size": 12, "border": 1,
                                 "align": "right",
                                 "num_format": {"amt": "#,##0.00;(#,##0.00);-",
                                                "qty": "#,##0",
                                                "pct": "0.0%;(0.0%);-",
                                                "prc": "#,##0.00"}[kind]})
            ws.write(r, 1, val, fmt)
        r += 1

    # --- period detail, the core ask ---
    ws, r0, last = write_sheet(
        wb, "National by Period",
        "National Sales by Fiscal Period",
        "One row per fiscal period. POP_PCT is versus the previous period. "
        "YOY_PCT is versus the same period one year earlier, blank where no prior year exists.",
        per, f, total_cols=["SL_AMT", "SL_QTY"])

    ch = wb.add_chart({"type": "line"})
    ch.add_series({
        "name": "Sales amount",
        "categories": ["National by Period", r0 + 1, 0, last, 0],
        "values": ["National by Period", r0 + 1, 4, last, 4],
        "line": {"color": "#1F3864", "width": 2},
    })
    ch.set_title({"name": "National sales by period"})
    ch.set_x_axis({"name": "Fiscal period", "num_font": {"rotation": -45, "size": 8}})
    ch.set_y_axis({"name": "Sales amount", "num_format": "#,##0"})
    ch.set_size({"width": 1000, "height": 380})
    ch.set_legend({"none": True})
    ws.insert_chart(last + 4, 1, ch)

    # --- remaining sheets ---
    write_sheet(wb, "Year Summary", "Fiscal Year Summary",
                "PERIODS shows how many periods each year contributes. Years marked partial "
                "are not comparable on a full-year basis.",
                yr, f, total_cols=["SL_AMT", "SL_QTY"])

    if len(yoy):
        write_sheet(wb, "YoY Comparable", "Year over Year, Comparable Periods Only",
                    "Each year is compared to the prior year using only the periods present in "
                    "both. This is the correct read on growth when a year is incomplete.",
                    yoy, f)

    write_sheet(wb, "Quarter Summary", "Sales by Fiscal Quarter",
                "PERIODS per quarter varies with the 13-period calendar. Compare AMT_PER_PERIOD, "
                "not raw quarter totals.",
                qtr, f, total_cols=["SL_AMT", "SL_QTY"])

    ws2, r2, l2 = write_sheet(
        wb, "By Territory", "Sales by Territory",
        "YOY_COMP_PCT compares FY" + str(cy) + " to FY" + str(py) + " on P"
        + str(min(both)) + "-P" + str(max(both)) + " only.",
        ter, f, total_cols=["SL_AMT", "SL_QTY"])

    cb = wb.add_chart({"type": "column"})
    cb.add_series({
        "name": "Sales by territory",
        "categories": ["By Territory", r2 + 1, 0, l2, 0],
        "values": ["By Territory", r2 + 1, ter.columns.get_loc("SL_AMT"), l2,
                   ter.columns.get_loc("SL_AMT")],
        "fill": {"color": "#1F3864"},
    })
    cb.set_title({"name": "Total sales by territory"})
    cb.set_y_axis({"num_format": "#,##0"})
    cb.set_size({"width": 800, "height": 340})
    cb.set_legend({"none": True})
    ws2.insert_chart(l2 + 4, 1, cb)

    write_sheet(wb, "By Article", "Sales by Article",
                "Ranked by total sales. CUM_SHARE shows concentration. CURR/PRIOR compare FY"
                + str(cy) + " to FY" + str(py) + " on matched periods only.",
                art, f, total_cols=["SL_AMT", "SL_QTY"])

    write_sheet(wb, "Top Movers", "Largest Article Movements, Comparable Periods",
                "FY" + str(cy) + " vs FY" + str(py) + " on P" + str(min(both)) + "-P"
                + str(max(both)) + ". Articles with no prior-year sales are excluded, "
                "since percentage change is undefined.",
                mov, f)

    write_sheet(wb, "By Industry", "Sales by Industry Key",
                "Industry level roll-up across the full window.",
                ind, f, total_cols=["SL_AMT", "SL_QTY"])

    wb.close()
    print("written:", out)
    print("total SL_AMT: {:,.2f}".format(tot_amt), "| total SL_QTY: {:,.0f}".format(tot_qty))
    return {"period": per, "year": yr, "terr": ter, "article": art, "industry": ind,
            "movers": mov, "yoy": yoy, "base": b}


if __name__ == "__main__":
    pass
