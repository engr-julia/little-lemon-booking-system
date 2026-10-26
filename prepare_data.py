"""Clean LittleLemon_data.xlsx and write normalised CSVs for MySQL."""
import pandas as pd, sys
from unidecode import unidecode   # pip install unidecode


def _to_bytes(x):
    """Map each char back to the byte it was misread from (cp1252, with the
    five cp1252-undefined bytes 0x81/8D/8F/90/9D falling back to latin-1)."""
    out = bytearray()
    for ch in x:
        try:
            out += ch.encode('cp1252')
        except UnicodeEncodeError:
            if ord(ch) < 256:
                out.append(ord(ch))
            else:
                raise
    return bytes(out)


def fix_text(x):
    """Repair UTF-8-read-as-cp1252 mojibake, then transliterate to plain ASCII
    (MySQL Workbench's import wizard fails on non-ASCII bytes on Windows)."""
    if not isinstance(x, str):
        return x
    try:
        x = _to_bytes(x).decode('utf-8')
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass
    return unidecode(x).strip()


src = sys.argv[1]
out = sys.argv[2]
d = pd.read_excel(src, keep_default_na=False, na_values=[''])
d.columns = [c.strip() for c in d.columns]          # ' Cost' -> 'Cost'
d['Postal Code'] = d['Postal Code'].astype('string').str.strip()

# Cuisines
cuisines = pd.DataFrame({'CuisineName': sorted(d['Cuisine Name'].unique())})
cuisines.insert(0, 'CuisineID', range(1, len(cuisines)+1))

# Menu items (one table, typed)
items = []
for col, t in [('Course Name','Course'),('Starter Name','Starter'),
               ('Desert Name','Dessert'),('Drink','Drink'),('Sides','Side')]:
    for n in sorted(d[col].unique()):
        items.append((t, n))
mi = pd.DataFrame(items, columns=['ItemType','ItemName'])
mi.insert(0, 'MenuItemID', range(1, len(mi)+1))
key = {(r.ItemType, r.ItemName): r.MenuItemID for r in mi.itertuples()}
cmap = dict(zip(cuisines.CuisineName, cuisines.CuisineID))

# Customers
for c in ['Customer Name','City','Country']:
    d[c] = d[c].map(fix_text)
cust = (d[['Customer ID','Customer Name','City','Country','Country Code']]
        .drop_duplicates('Customer ID')
        .rename(columns={'Customer ID':'CustomerID','Customer Name':'FullName',
                         'Country Code':'CountryCode'}))

# Orders (one row per source row; OrderID repeats)
o = pd.DataFrame({
  'OrderLineID': d['Row Number'],
  'OrderID': d['Order ID'],
  'CustomerID': d['Customer ID'],
  'OrderDate': d['Order Date'].dt.strftime('%Y-%m-%d'),
  'DeliveryDate': d['Delivery Date'].dt.strftime('%Y-%m-%d'),
  'PostalCode': d['Postal Code'],
  'Cost': d['Cost'], 'Sales': d['Sales'], 'Quantity': d['Quantity'],
  'Discount': d['Discount'], 'DeliveryCost': d['Delivery Cost'],
  'CuisineID': d['Cuisine Name'].map(cmap),
  'CourseID':  [key[('Course',x)]  for x in d['Course Name']],
  'StarterID': [key[('Starter',x)] for x in d['Starter Name']],
  'DessertID': [key[('Dessert',x)] for x in d['Desert Name']],
  'DrinkID':   [key[('Drink',x)]   for x in d['Drink']],
  'SideID':    [key[('Side',x)]    for x in d['Sides']],
})
for name, df in [('cuisines',cuisines),('menu_items',mi),('customers',cust),('orders',o)]:
    df.to_csv(f'{out}/{name}.csv', index=False, na_rep='\\N')
    print(name, len(df))
print('Country code NA kept:', (cust.CountryCode=='NA').sum())
